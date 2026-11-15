import Foundation

/// A job as GitLab reports it, with its pipeline and the runner that picked it up.
struct GitLabJob: Codable, Sendable, Hashable {
    struct PipelineRef: Codable, Sendable, Hashable {
        let id: Int
        let status: String
    }

    struct Runner: Codable, Sendable, Hashable {
        let id: Int
        let description: String?
    }

    struct Commit: Codable, Sendable, Hashable {
        let title: String?
    }

    let id: Int
    let name: String
    let stage: String?
    let status: String
    let createdAt: Date?
    let startedAt: Date?
    let finishedAt: Date?
    let tagList: [String]?
    let webURL: URL?
    let runner: Runner?
    let pipeline: PipelineRef?
    let commit: Commit?
    let user: GitLabUser?

    enum CodingKeys: String, CodingKey {
        case id, name, stage, status, runner, pipeline, commit, user
        case createdAt = "created_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case tagList = "tag_list"
        case webURL = "web_url"
    }

    var job: Job {
        Job(
            id: String(id),
            name: name,
            stage: stage,
            status: RunStatus(gitLab: status),
            conclusion: Conclusion(gitLab: status),
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: finishedAt,
            labels: tagList ?? [],
            runner: runner.map { $0.description ?? "#\($0.id)" },
            webURL: webURL
        )
    }
}
