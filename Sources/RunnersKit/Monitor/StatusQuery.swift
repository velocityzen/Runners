/// What to look at, and how hard.
public struct StatusQuery: Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        /// Every repository the token's user owns.
        case authenticatedUser
        /// Every repository of a user or organization.
        case owner(String)
        /// These repositories, by `owner/name`.
        case repositories([String])
    }

    public var target: Target
    /// Run statuses to look for; each costs one request per repository.
    public var statuses: [ActionStatus]
    public var includeJobs: Bool
    public var includeForks: Bool
    /// How many requests may run at the same time.
    public var concurrency: Int

    public init(
        target: Target = .authenticatedUser,
        statuses: [ActionStatus] = ActionStatus.active,
        includeJobs: Bool = true,
        includeForks: Bool = false,
        concurrency: Int = 16
    ) {
        self.target = target
        self.statuses = statuses
        self.includeJobs = includeJobs
        self.includeForks = includeForks
        self.concurrency = max(1, concurrency)
    }
}
