import Foundation

/// A machine that picks up jobs: a self-hosted runner, a pool of larger runners GitHub runs for
/// an organization, or a GitLab runner.
public struct Runner: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        /// Registered with GitHub by its owner, or by a runner vendor.
        case selfHosted = "self_hosted"
        /// A pool of larger runners that GitHub runs for an organization.
        case githubHosted = "github_hosted"
        /// GitLab: shared by the whole instance.
        case instance
        /// GitLab: a group's, for its projects and subgroups.
        case group
        /// GitLab: a project's own.
        case project
    }

    /// Whether the service hears from it.
    public enum Status: String, Codable, Sendable {
        case online
        case offline
        /// GitLab: not heard from in over a week.
        case stale
        /// GitLab: registered, never heard from.
        case neverContacted = "never_contacted"
        /// GitHub: a pool of larger runners being set up.
        case provisioning
        case unknown

        /// `never contacted`
        public var phrase: String {
            rawValue.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// What it is doing, as far as the service says. The report groups runners by it.
    public enum State: String, Codable, Sendable, CaseIterable, Comparable {
        case busy
        case idle
        case paused
        case offline

        public static func < (lhs: State, rhs: State) -> Bool {
            allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
        }
    }

    public let id: String
    public let name: String
    public let kind: Kind
    public let status: Status
    /// On a job now. `nil` when the service doesn't say, as for GitHub's larger runners.
    public let busy: Bool?
    /// Takes no new jobs until it is resumed.
    public let paused: Bool
    /// Takes one job and then goes away, as a runner vendor's do.
    public let ephemeral: Bool
    /// The labels it answers to. GitLab lists runners without their tags.
    public let labels: [String]
    /// Its OS, platform or machine size, when the service gives one.
    public let details: String?
    /// The runner vendor its labels name, if any.
    public let host: RunnerHost?
    /// The jobs it is on, when the service says. GitHub doesn't.
    public let jobs: [RunnerJob]
    public let state: State

    public init(
        id: String,
        name: String,
        kind: Kind,
        status: Status,
        busy: Bool?,
        paused: Bool = false,
        ephemeral: Bool = false,
        labels: [String] = [],
        details: String? = nil,
        jobs: [RunnerJob] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.status = status
        self.busy = busy
        self.paused = paused
        self.ephemeral = ephemeral
        self.labels = labels
        self.details = details
        self.host = RunnerHost(labels: labels)
        self.jobs = jobs
        self.state = Self.state(status: status, busy: busy ?? !jobs.isEmpty, paused: paused)
    }

    /// Offline unless the service hears from it; then paused, busy or idle. A paused runner
    /// can still be finishing a job, and shows as busy until it has.
    static func state(status: Status, busy: Bool, paused: Bool) -> State {
        guard status == .online else { return .offline }
        if busy { return .busy }
        return paused ? .paused : .idle
    }
}

/// A job a runner is on.
public struct RunnerJob: Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    /// The full name of its repository or project.
    public let repository: String?
    public let webURL: URL?

    public init(id: String, name: String, repository: String?, webURL: URL?) {
        self.id = id
        self.name = name
        self.repository = repository
        self.webURL = webURL
    }

    enum CodingKeys: String, CodingKey {
        case id, name, repository
        case webURL = "web_url"
    }
}
