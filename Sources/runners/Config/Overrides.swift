import RunnersKit

/// What the command line sets. `nil` or empty means not given, which leaves it to the config.
struct Overrides: Sendable {
    var provider: String?
    var owner: String?
    var repositories: [String] = []
    var statuses: [RunStatus] = []
    var jobs: Bool?
    var allJobs: Bool?
    var forks: Bool?
    var concurrency: Int?
    var interval: Int?
    var color: Bool?
    var programStatus: Bool?
    var cache: Bool?
    var apiURL: String?

    /// The owner or repositories given, if any.
    var target: StatusQuery.Target? {
        if !repositories.isEmpty { return .repositories(repositories) }
        return owner.map(StatusQuery.Target.owner)
    }
}
