import Foundation

/// A workflow run as GitHub reports it.
struct GitHubWorkflowRun: Codable, Sendable, Hashable {
    let id: Int
    let name: String?
    let displayTitle: String?
    let runNumber: Int
    let runAttempt: Int?
    let event: String
    let status: String
    let conclusion: String?
    let headBranch: String?
    let headSHA: String
    let htmlURL: URL
    let createdAt: Date
    let runStartedAt: Date?
    let updatedAt: Date?
    let actor: GitHubAccount?

    enum CodingKeys: String, CodingKey {
        case id, name, event, status, conclusion, actor
        case displayTitle = "display_title"
        case runNumber = "run_number"
        case runAttempt = "run_attempt"
        case headBranch = "head_branch"
        case headSHA = "head_sha"
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case runStartedAt = "run_started_at"
        case updatedAt = "updated_at"
    }

    var run: Run {
        Run(
            id: String(id),
            name: name ?? "Workflow",
            title: displayTitle,
            number: runNumber,
            attempt: runAttempt,
            trigger: event,
            status: RunStatus(gitHub: status),
            conclusion: conclusion.map(Conclusion.init(gitHub:)),
            branch: headBranch,
            commit: headSHA,
            webURL: htmlURL,
            createdAt: createdAt,
            startedAt: runStartedAt,
            // A finished run changes no more, so its last update is when it finished.
            completedAt: status == "completed" ? updatedAt : nil,
            actor: actor?.login
        )
    }
}

/// `GET /repos/{owner}/{repo}/actions/runs`
struct GitHubWorkflowRunsPage: PagedResponse, Codable {
    let workflowRuns: [GitHubWorkflowRun]

    var items: [GitHubWorkflowRun] { workflowRuns }

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}
