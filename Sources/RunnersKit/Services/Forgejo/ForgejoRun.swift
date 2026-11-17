import Foundation

/// A run from `GET /repos/{owner}/{repo}/actions/runs[/{id}]`.
struct ForgejoRun: Codable, Sendable, Hashable {
    struct Actor: Codable, Sendable, Hashable {
        let login: String
    }

    let id: Int
    let title: String?
    /// The workflow's file name, like `testing.yml`.
    let workflowID: String
    /// The number the web UI shows.
    let indexInRepo: Int?
    let triggerUser: Actor?
    /// The branch, tag or pull request (`#15054`) it ran on.
    let prettyref: String?
    let commitSHA: String?
    let event: String?
    /// `waiting`, `running`, `blocked`, `success`, `failure`, `cancelled`, `skipped` or
    /// `unknown`.
    let status: String
    /// A run from a fork or an untrusted user that someone has to approve.
    let needApproval: Bool?
    /// Who approved it, or 0.
    let approvedBy: Int?
    let created: Date
    let started: Date?
    let stopped: Date?
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case id, title, prettyref, event, status, created, started, stopped
        case workflowID = "workflow_id"
        case indexInRepo = "index_in_repo"
        case triggerUser = "trigger_user"
        case commitSHA = "commit_sha"
        case needApproval = "need_approval"
        case approvedBy = "approved_by"
        case htmlURL = "html_url"
    }

    /// Still waiting for someone to approve it.
    var awaitsApproval: Bool {
        needApproval == true && (approvedBy ?? 0) == 0
    }

    var run: Run {
        let status = RunStatus(forgejoRun: self.status, awaitsApproval: awaitsApproval)
        return Run(
            id: String(id),
            name: workflowID,
            title: title,
            number: indexInRepo,
            trigger: event,
            status: status,
            conclusion: status == .completed ? Conclusion(forgejo: self.status) : nil,
            branch: prettyref,
            commit: commitSHA,
            webURL: htmlURL,
            createdAt: created,
            startedAt: ForgejoTime.set(started),
            completedAt: status == .completed ? ForgejoTime.set(stopped) : nil,
            actor: triggerUser?.login
        )
    }
}

struct ForgejoRunsPage: Codable, Sendable {
    let totalCount: Int
    let workflowRuns: [ForgejoRun]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case workflowRuns = "workflow_runs"
    }
}

/// A job from `GET /repos/{owner}/{repo}/actions/runs/{id}/jobs`.
struct ForgejoJob: Codable, Sendable, Hashable {
    struct Step: Codable, Sendable, Hashable {
        let name: String
        let status: String?
        let started: Date?
        let stopped: Date?
    }

    let id: Int
    let name: String
    let status: String
    /// The labels it asks for.
    let runsOn: [String]?
    /// The task a runner took it as, or 0 while none has.
    let taskID: Int?
    let htmlURL: URL?
    /// Only when the job is read on its own: a `Set up job` step first, a `Complete job`
    /// step last, the workflow's steps between. A run's job list leaves them out.
    let steps: [Step]?

    enum CodingKeys: String, CodingKey {
        case id, name, status, steps
        case runsOn = "runs_on"
        case taskID = "task_id"
        case htmlURL = "html_url"
    }

    /// The jobs API gives no times of its own, so they come from the steps; a queued job
    /// shows how long its run has waited.
    func job(createdAt: Date) -> Job {
        let status = RunStatus(forgejoJob: self.status)
        let steps = steps ?? []
        return Job(
            id: String(id),
            name: name,
            status: status,
            conclusion: status == .completed ? Conclusion(forgejo: self.status) : nil,
            createdAt: createdAt,
            startedAt: steps.lazy.compactMap { ForgejoTime.set($0.started) }.first,
            completedAt: status == .completed
                ? steps.reversed().lazy.compactMap { ForgejoTime.set($0.stopped) }.first : nil,
            labels: runsOn ?? [],
            currentStep: status == .running
                ? steps.first { $0.status == "running" }?.name : nil,
            webURL: htmlURL
        )
    }
}

/// Forgejo writes an unset time as `0001-01-01T00:00:00Z` in places, or leaves it out.
enum ForgejoTime {
    static func set(_ date: Date?) -> Date? {
        date.flatMap { $0.timeIntervalSince1970 > 0 ? $0 : nil }
    }
}
