/// A CI service the monitor can ask: it knows how to find an owner's repositories and their
/// unfinished runs, and maps its own responses onto the shared domain types.
public protocol CIService: Sendable {
    var provider: any Provider { get }

    /// The repositories the query's target covers, minus those that cannot run CI.
    func scope(for query: StatusQuery) async -> Result<MonitorScope, RunnersError>

    /// The unfinished runs of these repositories, in any order, with jobs when the query asks.
    func activeRuns(
        in repositories: [Repository],
        query: StatusQuery
    ) async -> Result<[ActiveRun], RunnersError>

    /// The run as it is now, finished or not, with its jobs when the query asks. A watch asks
    /// once a run drops out of the active ones, to show how it ended.
    func latest(_ run: ActiveRun, query: StatusQuery) async -> Result<ActiveRun, RunnersError>

    /// The API quota left, when the service reports one.
    func rateLimit() async -> RateLimit?

    /// The runners of the query's target, for services that have their own.
    func runners(for query: StatusQuery) async -> Result<RunnerListing, RunnersError>
}

extension CIService {
    /// Fails: the service has no runners of its own to list.
    public func runners(for query: StatusQuery) async -> Result<RunnerListing, RunnersError> {
        .failure(
            .configuration(
                "\(provider.name) has no runners to list; --runners works with GitHub and GitLab."
            )
        )
    }
}

/// The repositories to check, and whose they are.
///
/// It changes slowly, so a watch reads it again only every few minutes.
public struct MonitorScope: Sendable, Hashable {
    /// `nil` for an explicit list of repositories.
    public let owner: Owner?
    /// The repositories that can run CI.
    public let repositories: [Repository]
    /// How many repositories the target covers, counting those without workflows.
    public let repositoryCount: Int

    public init(owner: Owner?, repositories: [Repository], repositoryCount: Int? = nil) {
        self.owner = owner
        self.repositories = repositories
        self.repositoryCount = repositoryCount ?? repositories.count
    }
}
