import FP
import FPRetry
import Foundation

/// AWS CodeBuild's runner projects: each GitHub Actions job they take runs as one build, which
/// shows as a run with one job. Reads one region, through the CodeBuild API.
public struct AWSService: CIService {
    /// The API, once the endpoint names a region and the credentials can be read; otherwise
    /// the failure every call gives.
    let codeBuild: Result<CodeBuildAPI, RunnersError>
    let now: @Sendable () -> Date

    public var provider: any Provider { AWSProvider() }

    /// - Parameters:
    ///   - refresh: Fetches new credentials, for ones that expire: it is called within five
    ///     minutes of their ``AWSCredentials/expiration``, so a long watch keeps working. Calls
    ///     sign with the old ones while a failed fetch is retried, at most every 30 seconds,
    ///     and fail with its failure once they have expired. Nil, credentials are used as
    ///     they are.
    ///   - endpoint: CodeBuild's in one region, such as
    ///     `https://codebuild.us-east-1.amazonaws.com`, whose region signs the requests.
    public init(
        credentials: AWSCredentials,
        refresh: (@Sendable () async -> Result<AWSCredentials, RunnersError>)? = nil,
        endpoint: URL,
        transport: any HTTPTransport = URLSessionTransport(),
        retryPolicy: RetryPolicy = APIClient.defaultRetryPolicy,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.init(
            credentials: .success(credentials),
            refresh: refresh,
            endpoint: endpoint,
            transport: transport,
            retryPolicy: retryPolicy,
            now: now
        )
    }

    /// With credentials in their token form, as ``AWSProvider`` passes them.
    init(
        credentials: Result<AWSCredentials, RunnersError>,
        refresh: AWSCredentialsSource.Fetch? = nil,
        endpoint: URL,
        transport: any HTTPTransport,
        retryPolicy: RetryPolicy = APIClient.defaultRetryPolicy,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let region = Result<AWSRegion, RunnersError>.fromOptional(
            AWSRegion(codeBuildEndpoint: endpoint),
            error: .configuration(
                "\(endpoint.absoluteString) names no AWS region; "
                    + "use https://codebuild.<region>.amazonaws.com, or set AWS_REGION"
            )
        )
        codeBuild = flatten(region, credentials).map { region, credentials in
            CodeBuildAPI(
                client: AWSJSONClient(
                    endpoint: endpoint,
                    target: "CodeBuild_20161006",
                    credentials: AWSCredentialsSource(credentials, refresh: refresh),
                    region: region.name,
                    service: "codebuild",
                    transport: transport,
                    retryPolicy: retryPolicy,
                    now: now
                ),
                region: region
            )
        }
        self.now = now
    }

    /// CodeBuild has no quota to report: it throttles instead.
    public func rateLimit() async -> RateLimit? {
        nil
    }
}

extension AWSService {
    /// By default every runner project in the region; with repositories, the projects named,
    /// runner projects or not. CodeBuild has no owners.
    public func scope(for query: StatusQuery) async -> Result<MonitorScope, RunnersError> {
        await codeBuild.flatMapAsync { api in
            switch query.target {
                case .authenticatedUser:
                    await api.runnerProjects(concurrency: query.concurrency)

                case .owner(let owner):
                    .failure(
                        .configuration(
                            "AWS CodeBuild has no owners, so \"\(owner)\" names nothing: leave "
                                + "it out to watch every runner project in the region, or name "
                                + "projects with --repo"
                        )
                    )

                case .repositories(let names):
                    await api.projects(named: names, concurrency: query.concurrency)
            }
        }
    }

    /// For each project, its builds from the newest, until they are older than the longest a
    /// build of it can go on; each needs a listing and a read per hundred builds.
    public func activeRuns(
        in repositories: [Repository],
        query: StatusQuery
    ) async -> Result<[ActiveRun], RunnersError> {
        let now = now()
        return await codeBuild.flatMapAsync { api in
            await api.activeRuns(in: repositories, query: query, now: now)
        }
    }

    public func latest(
        _ run: ActiveRun,
        query: StatusQuery
    ) async -> Result<ActiveRun, RunnersError> {
        await codeBuild.flatMapAsync { api in
            await api.builds([run.run.id])
                .flatMap {
                    .fromOptional($0.first, error: .notFound("CodeBuild build \(run.run.id)"))
                }
                .map {
                    $0.activeRun(
                        in: run.repository,
                        region: api.region,
                        includeJobs: query.includeJobs
                    )
                }
        }
    }
}

extension CodeBuildAPI {
    func runnerProjects(concurrency: Int) async -> Result<MonitorScope, RunnersError> {
        await projectNames()
            .flatMapAsync { names in
                await projects(names, concurrency: concurrency)
                    .map { projects in
                        MonitorScope(
                            owner: nil,
                            repositories: projects.found.filter(\.isRunnerProject)
                                .map { $0.repository(in: region) },
                            repositoryCount: names.count
                        )
                    }
            }
    }

    /// The projects by name, in the order given; a name that names none is a failure.
    func projects(
        named names: [String],
        concurrency: Int
    ) async -> Result<MonitorScope, RunnersError> {
        await projects(names, concurrency: concurrency)
            .flatMap { projects in
                if let missing = projects.missing.first {
                    return .failure(.notFound("CodeBuild project \(missing) in \(region)"))
                }
                let byName = Dictionary(
                    projects.found.map { ($0.name, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                return .success(
                    MonitorScope(
                        owner: nil,
                        repositories: names.compactMap { byName[$0]?.repository(in: region) }
                    )
                )
            }
    }

    func activeRuns(
        in repositories: [Repository],
        query: StatusQuery,
        now: Date
    ) async -> Result<[ActiveRun], RunnersError> {
        let api = self
        let byName = Dictionary(
            repositories.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return await projects(repositories.map(\.id), concurrency: query.concurrency)
            .flatMapAsync { projects in
                await projects.found.traverseAsync(concurrency: query.concurrency) { project in
                    await api.unfinishedBuilds(
                        of: project.name,
                        startedAfter: now.addingTimeInterval(-project.lifetime)
                    )
                }
            }
            .map { builds in
                builds.joined()
                    .compactMap { build in
                        byName[build.project].map {
                            build.activeRun(in: $0, region: region, includeJobs: query.includeJobs)
                        }
                    }
                    .filter { query.statuses.contains($0.run.status) }
            }
    }

    /// The unfinished builds among a project's newest, page after page, until a page reaches
    /// back to `cutoff`: a build started before it has finished.
    func unfinishedBuilds(
        of project: String,
        startedAfter cutoff: Date,
        after token: String? = nil
    ) async -> Result<[CodeBuildBuild], RunnersError> {
        await buildIDs(of: project, after: token)
            .flatMapAsync { page in
                await builds(page.ids ?? [])
                    .flatMapAsync { builds in
                        let unfinished = builds.filter { !$0.isComplete }
                        let reachesCutoff = builds.contains {
                            ($0.startTime ?? .distantPast) < cutoff
                        }
                        guard let next = page.nextToken, !builds.isEmpty, !reachesCutoff else {
                            return .success(unfinished)
                        }
                        return await unfinishedBuilds(
                            of: project,
                            startedAfter: cutoff,
                            after: next
                        )
                        .map { unfinished + $0 }
                    }
            }
    }
}
