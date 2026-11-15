import Foundation

/// A job as GitHub reports it, with the runner that picked it up.
struct GitHubWorkflowJob: Codable, Sendable, Hashable {
    struct Step: Codable, Sendable, Hashable {
        let number: Int
        let name: String
        let status: String
    }

    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let createdAt: Date?
    let startedAt: Date?
    let completedAt: Date?
    let labels: [String]
    let runnerName: String?
    let htmlURL: URL?
    let steps: [Step]?

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion, labels, steps
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case runnerName = "runner_name"
        case htmlURL = "html_url"
    }

    var job: Job {
        Job(
            id: String(id),
            name: name,
            status: RunStatus(gitHub: status),
            conclusion: conclusion.map(Conclusion.init(gitHub:)),
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: completedAt,
            labels: labels,
            runner: runnerName,
            currentStep: steps?.first { $0.status == "in_progress" }?.name,
            webURL: htmlURL
        )
    }
}

/// `GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs`
struct GitHubWorkflowJobsPage: PagedResponse, Codable {
    let jobs: [GitHubWorkflowJob]

    var items: [GitHubWorkflowJob] { jobs }
}
