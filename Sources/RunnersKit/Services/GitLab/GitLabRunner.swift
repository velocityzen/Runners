import Foundation

/// A runner from `GET /runners`, `/groups/:id/runners` or `/projects/:id/runners`. The lists
/// leave out its tags.
struct GitLabRunner: Codable, Sendable, Hashable {
    let id: Int
    let description: String?
    let name: String?
    let paused: Bool?
    /// Before GitLab 14.8, the opposite of `paused`.
    let active: Bool?
    /// `instance_type`, `group_type` or `project_type`.
    let runnerType: String?
    let online: Bool?
    /// `online`, `offline`, `stale` or `never_contacted`; once also `active` and `paused`.
    let status: String?
    /// `idle` when it is on no job; GitLab 17.4 and later.
    let jobExecutionStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, description, name, paused, active, online, status
        case runnerType = "runner_type"
        case jobExecutionStatus = "job_execution_status"
    }

    /// Before GitLab 17.4, which doesn't say, `nil`.
    var isBusy: Bool? {
        jobExecutionStatus.map { $0 != "idle" }
    }

    func runner(jobs: [RunnerJob] = []) -> Runner {
        Runner(
            id: String(id),
            name: [description, name].compactMap(\.self).first { !$0.isEmpty } ?? "runner \(id)",
            kind: kind,
            status: runnerStatus,
            busy: isBusy,
            paused: paused ?? (status == "paused" || active == false),
            jobs: jobs
        )
    }

    var kind: Runner.Kind {
        switch runnerType {
            case "instance_type": .instance
            case "group_type": .group
            default: .project
        }
    }

    var runnerStatus: Runner.Status {
        switch status {
            case "online": .online
            case "offline": .offline
            case "stale": .stale
            case "never_contacted": .neverContacted
            default: online.map { $0 ? .online : .offline } ?? .unknown
        }
    }
}

/// A job from `GET /runners/:id/jobs`.
struct GitLabRunnerJob: Codable, Sendable, Hashable {
    struct Project: Codable, Sendable, Hashable {
        let pathWithNamespace: String?

        enum CodingKeys: String, CodingKey {
            case pathWithNamespace = "path_with_namespace"
        }
    }

    let id: Int
    let name: String
    let webURL: URL?
    let project: Project?

    enum CodingKeys: String, CodingKey {
        case id, name, project
        case webURL = "web_url"
    }

    var job: RunnerJob {
        RunnerJob(
            id: String(id),
            name: name,
            repository: project?.pathWithNamespace,
            webURL: webURL
        )
    }
}
