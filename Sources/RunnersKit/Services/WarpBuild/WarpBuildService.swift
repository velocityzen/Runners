import FP
import FPRetry
import Foundation

/// WarpBuild's runner instances: each GitHub Actions job a runner set takes runs on an
/// instance of its own, which shows as a run with one job, grouped by runner set as CodeBuild
/// builds group by project.
public struct WarpBuildService: CIService {
    let api: WarpBuildAPI

    public var provider: any Provider { WarpBuildProvider() }

    /// - Parameters:
    ///   - key: a WarpBuild API key with the CI scope, `wkey-…`.
    ///   - baseURL: the API, `https://api.warpbuild.com/api/v1` unless `WARPBUILD_API_URL`
    ///     says otherwise.
    public init(
        key: String,
        baseURL: URL = WarpBuildService.defaultBaseURL,
        transport: any HTTPTransport = ConditionalTransport(URLSessionTransport()),
        retryPolicy: RetryPolicy = APIClient.defaultRetryPolicy
    ) {
        api = WarpBuildAPI(
            client: APIClient(
                baseURL: baseURL,
                headers: WarpBuildAPI.headers(key: key),
                transport: transport,
                retryPolicy: retryPolicy,
                classify: WarpBuildAPI.classify
            )
        )
    }

    /// `https://api.warpbuild.com/api/v1`
    public static var defaultBaseURL: URL {
        URL(string: "https://api.warpbuild.com/api/v1") ?? URL(filePath: "/")
    }

    /// WarpBuild reports no quota.
    public func rateLimit() async -> RateLimit? {
        nil
    }
}

extension WarpBuildService {
    /// The organization's active runner sets, and those of its latest instances that
    /// `GET /runners` leaves out, such as WarpBuild's stock runners. With repositories, the
    /// runner sets they name, by ID, name or label. WarpBuild has no owners.
    public func scope(for query: StatusQuery) async -> Result<MonitorScope, RunnersError> {
        switch query.target {
            case .authenticatedUser:
                await known()
                    .map { sets, seen in
                        let active = sets.filter { $0.active != false }.map(\.repository)
                        return MonitorScope(
                            owner: nil,
                            repositories: active + seen,
                            repositoryCount: sets.count + seen.count
                        )
                    }

            case .owner(let owner):
                .failure(
                    .configuration(
                        "WarpBuild has no owners, so \"\(owner)\" names nothing: leave it out to "
                            + "watch every runner set, or name runner sets with --repo"
                    )
                )

            case .repositories(let names):
                await known()
                    .flatMap { sets, seen in
                        names.traverse { name in
                            Result.fromOptional(
                                sets.first { $0.isNamed(name) }?.repository
                                    ?? seen.first {
                                        [$0.id, $0.name].contains {
                                            $0.lowercased() == name.lowercased()
                                        }
                                    },
                                error: .notFound("WarpBuild runner set \(name)")
                            )
                        }
                    }
                    .map { MonitorScope(owner: nil, repositories: $0.uniqued(by: \.id)) }
        }
    }

    /// The runner sets `GET /runners` lists, and those of the latest instances it doesn't.
    func known() async -> Result<(sets: [WarpBuildRunnerSet], seen: [Repository]), RunnersError> {
        await withAll(await api.runnerSets(), await api.instances(statuses: []))
            .map { sets, instances in
                let listed = Set(sets.map(\.id))
                let seen = instances.filter { !listed.contains($0.groupID) }
                    .map(\.group)
                    .uniqued(by: \.id)
                return (sets: sets, seen: seen)
            }
    }

    /// `GET /runner_instance` for the allocating, allocated and running instances, every
    /// page, kept to the scope's runner sets.
    public func activeRuns(
        in repositories: [Repository],
        query: StatusQuery
    ) async -> Result<[ActiveRun], RunnersError> {
        let statuses = query.statuses.flatMap(\.warpBuildValues).uniqued(by: \.self)
        // No statuses would ask for every instance, idle and gone ones too.
        guard !statuses.isEmpty, !repositories.isEmpty else { return .success([]) }
        let byID = Dictionary(
            repositories.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return await api.instances(statuses: statuses)
            .map { instances in
                instances.compactMap { instance in
                    byID[instance.groupID].map {
                        instance.activeRun(in: $0, includeJobs: query.includeJobs)
                    }
                }
                .filter { query.statuses.contains($0.run.status) }
            }
    }

    /// The instance read again. It doesn't say how its job ended, so a finished run has no
    /// conclusion.
    public func latest(_ run: ActiveRun, query: StatusQuery) async -> Result<
        ActiveRun, RunnersError
    > {
        await api.instance(run.run.id)
            .map { $0.activeRun(in: run.repository, includeJobs: query.includeJobs) }
    }
}
