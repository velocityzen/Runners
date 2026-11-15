import Foundation

/// One job of a run, and the runner that picked it up.
public struct Job: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// The GitLab stage it belongs to.
    public let stage: String?
    public let status: RunStatus
    public let conclusion: Conclusion?
    public let createdAt: Date?
    public let startedAt: Date?
    public let completedAt: Date?
    /// What it needs from a runner: GitHub `runs-on` labels, GitLab tags.
    public let labels: [String]
    /// The runner that picked it up.
    public let runner: String?
    /// The step running right now, where the service reports steps.
    public let currentStep: String?
    public let webURL: URL?

    public init(
        id: String,
        name: String,
        stage: String? = nil,
        status: RunStatus,
        conclusion: Conclusion? = nil,
        createdAt: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        labels: [String] = [],
        runner: String? = nil,
        currentStep: String? = nil,
        webURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.stage = stage
        self.status = status
        self.conclusion = conclusion
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.labels = labels
        self.runner = runner
        self.currentStep = currentStep
        self.webURL = webURL
    }

    enum CodingKeys: String, CodingKey {
        case id, name, stage, status, conclusion, labels, runner
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case currentStep = "current_step"
        case webURL = "web_url"
    }

    /// Finished with nothing to look at.
    public var hasPassed: Bool {
        status == .completed && conclusion?.hasPassed == true
    }
}
