import Foundation

/// One job of a workflow run, and the runner that picked it up.
public struct WorkflowJob: Codable, Sendable, Hashable, Identifiable {
    public struct Step: Codable, Sendable, Hashable {
        public let number: Int
        public let name: String
        public let status: ActionStatus
        public let conclusion: Conclusion?

        public init(number: Int, name: String, status: ActionStatus, conclusion: Conclusion? = nil) {
            self.number = number
            self.name = name
            self.status = status
            self.conclusion = conclusion
        }
    }

    public let id: Int
    public let runID: Int
    public let name: String
    public let status: ActionStatus
    public let conclusion: Conclusion?
    public let createdAt: Date?
    public let startedAt: Date?
    public let completedAt: Date?
    public let labels: [String]
    public let runnerName: String?
    public let runnerGroupName: String?
    public let htmlURL: URL?
    public let steps: [Step]?

    public init(
        id: Int,
        runID: Int,
        name: String,
        status: ActionStatus,
        conclusion: Conclusion? = nil,
        createdAt: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        labels: [String] = [],
        runnerName: String? = nil,
        runnerGroupName: String? = nil,
        htmlURL: URL? = nil,
        steps: [Step]? = nil
    ) {
        self.id = id
        self.runID = runID
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.labels = labels
        self.runnerName = runnerName
        self.runnerGroupName = runnerGroupName
        self.htmlURL = htmlURL
        self.steps = steps
    }

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion, labels, steps
        case runID = "run_id"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case runnerName = "runner_name"
        case runnerGroupName = "runner_group_name"
        case htmlURL = "html_url"
    }

    /// The step running right now.
    public var currentStep: Step? {
        steps?.first { $0.status == .inProgress }
    }
}

/// `GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs`
struct WorkflowJobsPage: PagedResponse {
    let jobs: [WorkflowJob]

    var items: [WorkflowJob] { jobs }
}
