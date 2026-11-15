import Foundation

/// One run of a pipeline: a GitHub workflow run, a GitLab pipeline.
public struct Run: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// The workflow or pipeline name.
    public let name: String
    /// What the run is about, usually the commit or pull request title.
    public let title: String?
    /// The number people use for it: GitHub's run number, GitLab's pipeline IID.
    public let number: Int?
    public let attempt: Int?
    /// What started it: `push`, `schedule`, `merge_request_event`, …
    public let trigger: String?
    public let status: RunStatus
    public let conclusion: Conclusion?
    public let branch: String?
    public let commit: String?
    public let webURL: URL
    public let createdAt: Date
    public let startedAt: Date?
    /// The handle of who started it.
    public let actor: String?

    public init(
        id: String,
        name: String,
        title: String? = nil,
        number: Int? = nil,
        attempt: Int? = nil,
        trigger: String? = nil,
        status: RunStatus,
        conclusion: Conclusion? = nil,
        branch: String? = nil,
        commit: String? = nil,
        webURL: URL,
        createdAt: Date,
        startedAt: Date? = nil,
        actor: String? = nil
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.number = number
        self.attempt = attempt
        self.trigger = trigger
        self.status = status
        self.conclusion = conclusion
        self.branch = branch
        self.commit = commit
        self.webURL = webURL
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.actor = actor
    }

    enum CodingKeys: String, CodingKey {
        case id, name, title, number, attempt, trigger, status, conclusion, branch, commit, actor
        case webURL = "web_url"
        case createdAt = "created_at"
        case startedAt = "started_at"
    }
}
