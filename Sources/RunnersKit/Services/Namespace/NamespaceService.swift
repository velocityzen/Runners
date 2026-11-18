import FP
import FPRetry
import Foundation

/// GitHub Actions jobs on Namespace's runners, from Namespace's Connect API.
///
/// A runner profile, `runs-on: namespace-profile-<tag>`, starts an instance for each job, and
/// Namespace lists those jobs. A workflow run shows with its unfinished jobs on Namespace,
/// each with its profile, runner and instance and the machine its profile gives.
public struct NamespaceService: CIService {
    let api: NamespaceAPI

    public var provider: any Provider { NamespaceProvider() }

    /// - Parameters:
    ///   - token: a Namespace tenant token, such as one from `nsc token create`.
    ///   - baseURL: the API of the GitHub runner services, `https://global.namespaceapis.com`
    ///     unless `NSC_GLOBAL_ENDPOINT` or `NAMESPACE_API_URL` says otherwise.
    public init(
        token: String,
        baseURL: URL = NamespaceService.defaultBaseURL,
        transport: any HTTPTransport = ConditionalTransport(URLSessionTransport()),
        retryPolicy: RetryPolicy = APIClient.defaultRetryPolicy
    ) {
        api = NamespaceAPI(
            connect: ConnectClient(
                baseURL: baseURL,
                token: token,
                tokenHelp: NamespaceAPI.tokenHelp,
                rejectsToken: NamespaceAPI.rejectsToken,
                transport: transport,
                retryPolicy: retryPolicy
            )
        )
    }

    /// `https://global.namespaceapis.com`, which the GitHub runner services' protos name.
    public static var defaultBaseURL: URL {
        URL(string: "https://global.namespaceapis.com") ?? URL(filePath: "/")
    }

    /// Namespace reports no quota.
    public func rateLimit() async -> RateLimit? {
        nil
    }
}

extension NamespaceService {
    /// Namespace has no list of repositories, so the workspace's are those its latest hundred
    /// jobs, finished or not, were for, and an owner's are those named `owner/…`. A repository
    /// whose jobs are older shows once it runs again. `--repo` names repositories as they are.
    public func scope(for query: StatusQuery) async -> Result<MonitorScope, RunnersError> {
        switch query.target {
            case .authenticatedUser:
                await api.recentJobs()
                    .map { MonitorScope(owner: nil, repositories: Self.repositories(of: $0)) }

            case .owner(let name):
                await api.recentJobs()
                    .map { jobs in
                        MonitorScope(
                            owner: Owner(id: name, login: name, kind: .unknown),
                            repositories: Self.repositories(of: jobs)
                                .filter {
                                    $0.fullName.lowercased().hasPrefix(name.lowercased() + "/")
                                }
                        )
                    }

            case .repositories(let names):
                .success(
                    MonitorScope(
                        owner: nil,
                        repositories: names.map { Repository(gitHubFullName: $0) }
                    )
                )
        }
    }

    static func repositories(of jobs: [NamespaceJob]) -> [Repository] {
        jobs.compactMap(\.repository)
            .filter { !$0.isEmpty }
            .uniqued { $0.lowercased() }
            .map { Repository(gitHubFullName: $0) }
    }

    /// One `ListJobs` for the unfinished jobs, every page, kept to the scope's repositories.
    /// With jobs, `ListProfiles` once for the profiles' machines, and `DescribeJob` for each
    /// running job the listing gave no runner.
    public func activeRuns(
        in repositories: [Repository],
        query: StatusQuery
    ) async -> Result<[ActiveRun], RunnersError> {
        // A Namespace job is queued until it starts, then running.
        let wantsRunning = query.statuses.contains(.running)
        guard wantsRunning || query.statuses.contains(.queued), !repositories.isEmpty else {
            return .success([])
        }
        let byName = Dictionary(
            repositories.map { ($0.fullName.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let request = NamespaceListJobs(
            repository: query.target == .authenticatedUser
                ? nil : NamespaceStringMatcher(values: repositories.map(\.fullName)),
            hasNotStarted: wantsRunning ? nil : true,
            hasNotFinished: wantsRunning ? true : nil
        )
        return await api.jobs(request)
            .flatMapAsync { jobs in await described(jobs, query: query) }
            .flatMapAsync { jobs in
                await shapes(of: jobs, query: query)
                    .map { shapes in
                        NamespaceRun.runs(of: jobs).compactMap { run in
                            byName[run.repository.lowercased()].map {
                                run.activeRun(
                                    in: $0,
                                    shapes: shapes,
                                    includeJobs: query.includeJobs
                                )
                            }
                        }
                    }
            }
            .map { $0.filter { query.statuses.contains($0.run.status) } }
    }

    /// With jobs, each running job the listing gave no runner, read on its own.
    func described(
        _ jobs: [NamespaceJob],
        query: StatusQuery
    ) async -> Result<[NamespaceJob], RunnersError> {
        guard query.includeJobs else { return .success(jobs) }
        let api = api
        return await jobs.traverseAsync(concurrency: query.concurrency) { job in
            job.status == .running && job.runner == nil ? await api.job(job.id) : .success(job)
        }
    }

    /// With jobs that name a profile, the profiles' machines.
    func shapes(
        of jobs: [NamespaceJob],
        query: StatusQuery
    ) async -> Result<[String: NamespaceShape], RunnersError> {
        guard query.includeJobs, jobs.contains(where: { $0.profileTag != nil }) else {
            return .success([:])
        }
        return await api.shapes()
    }

    /// The run's jobs again, with how they ended: `ListJobs` for its repository since its
    /// first job was created, kept to the run.
    public func latest(_ run: ActiveRun, query: StatusQuery) async -> Result<
        ActiveRun, RunnersError
    > {
        let since = run.run.createdAt.addingTimeInterval(-1)
        let request = NamespaceListJobs(
            timeRange: NamespaceTimeRange(after: ProtoTime.string(since)),
            repository: NamespaceStringMatcher(values: [run.repository.fullName])
        )
        return await api.jobs(request)
            .flatMap { jobs in
                let own = jobs.filter { $0.runId.map { String($0.value) } == run.run.id }
                return own.isEmpty
                    ? .failure(
                        .notFound(
                            "Namespace jobs of run \(run.run.id) in \(run.repository.fullName)"
                        )
                    )
                    : .success(
                        NamespaceRun(id: run.run.id, repository: run.repository.fullName, jobs: own)
                            .activeRun(
                                in: run.repository,
                                shapes: [:],
                                includeJobs: query.includeJobs
                            )
                    )
            }
    }
}
