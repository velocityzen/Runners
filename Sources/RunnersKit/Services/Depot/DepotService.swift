import FP
import FPRetry
import Foundation

/// GitHub Actions jobs on Depot's runners, from Depot's Connect API.
///
/// Depot knows a workflow run only by the jobs of it that it runs, so a run shows with those
/// jobs alone: its jobs on GitHub's own runners are left out, and it reads as finished once
/// its Depot jobs are.
public struct DepotService: CIService {
    let api: DepotAPI

    public var provider: any Provider { DepotProvider() }

    /// - Parameters:
    ///   - token: a Depot organization API token.
    ///   - baseURL: the API, `https://api.depot.dev` unless `DEPOT_API_URL` says otherwise.
    public init(
        token: String,
        baseURL: URL = DepotCIService.defaultBaseURL,
        transport: any HTTPTransport = ConditionalTransport(URLSessionTransport()),
        retryPolicy: RetryPolicy = APIClient.defaultRetryPolicy
    ) {
        api = DepotAPI(
            connect: ConnectClient(
                baseURL: baseURL,
                token: token,
                tokenHelp: DepotAPI.tokenHelp,
                transport: transport,
                retryPolicy: retryPolicy
            )
        )
    }

    /// Depot reports no quota.
    public func rateLimit() async -> RateLimit? {
        nil
    }
}

extension DepotService {
    /// The repositories the Depot GitHub App can see, on every account it is installed on, or
    /// on the owner's alone. `--repo` names repositories as they are.
    public func scope(for query: StatusQuery) async -> Result<MonitorScope, RunnersError> {
        switch query.target {
            case .authenticatedUser:
                await connections(owner: nil)
                    .flatMapAsync { await repositories(of: $0, owner: nil, query: query) }

            case .owner(let name):
                await connections(owner: name)
                    .flatMapAsync { connections in
                        await repositories(
                            of: connections,
                            owner: Owner(
                                id: name,
                                login: connections.first?.account ?? name,
                                kind: .unknown
                            ),
                            query: query
                        )
                    }

            case .repositories(let names):
                .success(MonitorScope(owner: nil, repositories: names.map(Repository.init(depot:))))
        }
    }

    /// The app's active installations, on the owner's account when one is named.
    func connections(owner: String?) async -> Result<[DepotGitHubConnection], RunnersError> {
        await api.gitHubConnections()
            .flatMap { found in
                let active = found.filter(\.isActive)
                guard let owner else { return .success(active) }
                let owned = active.filter { $0.account?.lowercased() == owner.lowercased() }
                guard owned.isEmpty else { return .success(owned) }
                let accounts = active.compactMap(\.account)
                return .failure(
                    .notFound(
                        "the Depot GitHub App is not installed on \(owner)"
                            + (accounts.isEmpty
                                ? "" : "; it is on \(accounts.joined(separator: ", "))")
                    )
                )
            }
    }

    func repositories(
        of connections: [DepotGitHubConnection],
        owner: Owner?,
        query: StatusQuery
    ) async -> Result<MonitorScope, RunnersError> {
        let api = api
        return await connections.traverseAsync(concurrency: query.concurrency) {
            await api.gitHubRepositories(of: $0)
        }
        .map { found in
            MonitorScope(
                owner: owner,
                repositories: found.flatMap { $0 }
                    .uniqued { $0.repository.lowercased() }
                    .map(\.domain)
            )
        }
    }

    /// One `ListGithubActionsJobs` for the unfinished jobs, every page, kept to the scope's
    /// repositories; with jobs, one more per run for its finished jobs too.
    public func activeRuns(
        in repositories: [Repository],
        query: StatusQuery
    ) async -> Result<[ActiveRun], RunnersError> {
        let statuses = query.statuses.compactMap(\.depotGitHubValue).uniqued(by: \.self)
        // An empty status list would ask for every job, finished ones too.
        guard !statuses.isEmpty, !repositories.isEmpty else { return .success([]) }
        let byName = Dictionary(
            repositories.map { ($0.fullName.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Every repository it is connected to, unless the query narrows them.
        let named = query.target == .authenticatedUser ? nil : repositories.map(\.fullName)
        return await api.gitHubJobs(statuses: statuses, repositories: named)
            .map { jobs in
                DepotGitHubRun.runs(of: jobs).compactMap { run in
                    byName[run.repository.lowercased()].map { (run: run, repository: $0) }
                }
            }
            .flatMapAsync { runs in await activeRuns(runs, query: query) }
            .map { $0.filter { query.statuses.contains($0.run.status) } }
    }

    func activeRuns(
        _ runs: [(run: DepotGitHubRun, repository: Repository)],
        query: StatusQuery
    ) async -> Result<[ActiveRun], RunnersError> {
        guard query.includeJobs else {
            return .success(runs.map { $0.run.activeRun(in: $0.repository, includeJobs: false) })
        }
        let api = api
        return await runs.traverseAsync(concurrency: query.concurrency) { listed in
            await api.gitHubJobs(ofRun: listed.run.id, in: listed.run.repository)
                .map { jobs in
                    DepotGitHubRun(
                        id: listed.run.id,
                        repository: listed.run.repository,
                        jobs: jobs.isEmpty ? listed.run.jobs : jobs
                    )
                    .activeRun(in: listed.repository, includeJobs: true)
                }
        }
    }

    /// The run's jobs on Depot again, with how they ended: one `ListGithubActionsJobs` for the
    /// run's ID.
    public func latest(_ run: ActiveRun, query: StatusQuery) async -> Result<
        ActiveRun, RunnersError
    > {
        await api.gitHubJobs(ofRun: run.run.id, in: run.repository.fullName)
            .flatMap { jobs in
                jobs.isEmpty
                    ? .failure(
                        .notFound("Depot jobs of run \(run.run.id) in \(run.repository.fullName)")
                    )
                    : .success(
                        DepotGitHubRun(
                            id: run.run.id,
                            repository: run.repository.fullName,
                            jobs: jobs
                        )
                        .activeRun(in: run.repository, includeJobs: query.includeJobs)
                    )
            }
    }
}
