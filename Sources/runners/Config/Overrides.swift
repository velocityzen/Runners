import RunnersKit

/// What the command line sets. `nil` or empty means not given, which leaves it to the config.
struct Overrides: Sendable {
    var provider: Provider?
    var owner: String?
    var repositories: [String] = []
    var statuses: [RunStatus] = []
    var jobs: Bool?
    var allJobs: Bool?
    var forks: Bool?
    var concurrency: Int?
    var interval: Int?
    var color: Bool?
    var apiURL: String?

    /// The owner or repositories given, if any.
    var target: StatusQuery.Target? {
        if !repositories.isEmpty { return .repositories(repositories) }
        return owner.map(StatusQuery.Target.owner)
    }
}

extension StatusQuery.Target {
    /// `owner/name`, or `group/…/project` on GitLab.
    static func isFullName(_ name: String) -> Bool {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty }
    }
}
