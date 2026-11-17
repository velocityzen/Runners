/// What to look at, and how hard.
public struct StatusQuery: Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        /// Every repository the token's user owns.
        case authenticatedUser
        /// Every repository of a user or organization (GitLab: group, subgroups included).
        case owner(String)
        /// These repositories, by full name.
        case repositories([String])
    }

    public var target: Target
    /// Run statuses to report.
    public var statuses: [RunStatus]
    public var includeJobs: Bool
    public var includeForks: Bool
    /// How many requests may run at the same time.
    public var concurrency: Int

    public init(
        target: Target = .authenticatedUser,
        statuses: [RunStatus] = RunStatus.active,
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

extension StatusQuery.Target {
    /// `owner/name`, or `group/…/name` where groups nest.
    public static func isFullName(_ name: String) -> Bool {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty }
    }
}
