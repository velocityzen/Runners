/// A CI service the monitor can ask: it knows how to find an owner's repositories and their
/// unfinished runs, and maps its own responses onto the shared domain types.
public protocol CIService: Sendable {
    var provider: Provider { get }

    /// The repositories the query's target covers, minus those that cannot run CI.
    func scope(for query: StatusQuery) async -> Result<MonitorScope, RunnersError>

    /// The unfinished runs of these repositories, in any order, with jobs when the query asks.
    func activeRuns(
        in repositories: [Repository],
        query: StatusQuery
    ) async -> Result<[ActiveRun], RunnersError>

    /// The API quota left, when the service reports one.
    func rateLimit() async -> RateLimit?
}

/// The repositories to check, and whose they are.
public struct MonitorScope: Sendable, Hashable {
    /// `nil` for an explicit list of repositories.
    public let owner: Owner?
    public let repositories: [Repository]

    public init(owner: Owner?, repositories: [Repository]) {
        self.owner = owner
        self.repositories = repositories
    }
}
