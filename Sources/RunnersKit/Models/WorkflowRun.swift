import Foundation

/// One run of a workflow.
public struct WorkflowRun: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String?
    public let displayTitle: String?
    public let runNumber: Int
    public let runAttempt: Int?
    public let event: String
    public let status: ActionStatus
    public let conclusion: Conclusion?
    public let headBranch: String?
    public let headSHA: String
    public let htmlURL: URL
    public let createdAt: Date
    public let updatedAt: Date
    public let runStartedAt: Date?
    public let actor: Account?

    public init(
        id: Int,
        name: String?,
        displayTitle: String? = nil,
        runNumber: Int,
        runAttempt: Int? = 1,
        event: String,
        status: ActionStatus,
        conclusion: Conclusion? = nil,
        headBranch: String?,
        headSHA: String,
        htmlURL: URL,
        createdAt: Date,
        updatedAt: Date,
        runStartedAt: Date? = nil,
        actor: Account? = nil
    ) {
        self.id = id
        self.name = name
        self.displayTitle = displayTitle
        self.runNumber = runNumber
        self.runAttempt = runAttempt
        self.event = event
        self.status = status
        self.conclusion = conclusion
        self.headBranch = headBranch
        self.headSHA = headSHA
        self.htmlURL = htmlURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.runStartedAt = runStartedAt
        self.actor = actor
    }

    enum CodingKeys: String, CodingKey {
        case id, name, event, status, conclusion, actor
        case displayTitle = "display_title"
        case runNumber = "run_number"
        case runAttempt = "run_attempt"
        case headBranch = "head_branch"
        case headSHA = "head_sha"
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case runStartedAt = "run_started_at"
    }
}

/// `GET /repos/{owner}/{repo}/actions/runs`
struct WorkflowRunsPage: PagedResponse {
    let workflowRuns: [WorkflowRun]

    var items: [WorkflowRun] { workflowRuns }

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}
