import Foundation

/// `GET /user`
struct WoodpeckerUser: Codable, Sendable, Hashable {
    let id: Int
    let login: String

    var owner: Owner {
        Owner(id: String(id), login: login, kind: .user)
    }
}

/// A repository from `GET /user/repos` or `GET /repos/lookup/{owner}/{name}`.
struct WoodpeckerRepository: Codable, Sendable, Hashable {
    struct LastPipeline: Codable, Sendable, Hashable {
        let number: Int
    }

    let id: Int
    let owner: String
    let name: String
    let fullName: String
    /// The repository on the forge.
    let forgeURL: URL?
    let isPrivate: Bool?
    /// Whether CI is turned on for it.
    let active: Bool?
    /// Only in `/user/repos`; absent for a repository that has never run.
    let lastPipeline: LastPipeline?

    enum CodingKeys: String, CodingKey {
        case id, owner, name, active
        case fullName = "full_name"
        case forgeURL = "forge_url"
        case isPrivate = "private"
        case lastPipeline = "last_pipeline"
    }

    func repository(server: URL) -> Repository {
        Repository(
            id: String(id),
            name: name,
            fullName: fullName,
            webURL: server.appending(path: "repos/\(id)"),
            isPrivate: isPrivate ?? false
        )
    }
}

/// A pipeline from `GET /repos/{id}/pipelines[/{number}]`. Only the single read has its
/// workflows.
struct WoodpeckerPipeline: Codable, Sendable, Hashable {
    let id: Int
    let number: Int
    /// `push`, `pull_request`, `tag`, `cron`, `manual`, …
    let event: String?
    let status: String
    let title: String?
    let message: String?
    let branch: String?
    let commit: String?
    let author: String?
    let sender: String?
    /// Unix seconds; 0 when it hasn't happened.
    let created: Int
    let started: Int?
    let finished: Int?
    let workflows: [WoodpeckerWorkflow]?

    func run(webURL: URL) -> Run {
        let status = RunStatus(woodpecker: self.status)
        let subject = title ?? message?.split(separator: "\n").first.map(String.init)
        return Run(
            id: String(number),
            name: "Pipeline",
            title: subject,
            number: number,
            trigger: event,
            status: status,
            conclusion: status == .completed ? Conclusion(woodpecker: self.status) : nil,
            branch: branch,
            commit: commit,
            webURL: webURL,
            createdAt: Date(timeIntervalSince1970: TimeInterval(created)),
            startedAt: WoodpeckerTime.date(started),
            completedAt: status == .completed ? WoodpeckerTime.date(finished) : nil,
            actor: sender ?? author
        )
    }
}

/// One workflow of a pipeline, which runs on one agent: shown as a job.
struct WoodpeckerWorkflow: Codable, Sendable, Hashable {
    let id: Int
    let name: String
    let state: String
    let started: Int?
    let finished: Int?
    /// 0 until an agent takes it.
    let agentID: Int?
    /// `linux/amd64`
    let platform: String?
    let children: [WoodpeckerStep]?

    enum CodingKeys: String, CodingKey {
        case id, name, state, started, finished, platform, children
        case agentID = "agent_id"
    }

    func job(createdAt: Date, webURL: URL) -> Job {
        let status = RunStatus(woodpecker: state)
        return Job(
            id: String(id),
            name: name,
            status: status,
            conclusion: status == .completed ? Conclusion(woodpecker: state) : nil,
            createdAt: createdAt,
            startedAt: WoodpeckerTime.date(started),
            completedAt: status == .completed ? WoodpeckerTime.date(finished) : nil,
            labels: platform.map { [$0] }?.filter { !$0.isEmpty } ?? [],
            runner: agentID.flatMap { $0 > 0 ? "agent \($0)" : nil },
            currentStep: status == .running
                ? children?.first { $0.state == "running" }?.name : nil,
            webURL: webURL
        )
    }
}

struct WoodpeckerStep: Codable, Sendable, Hashable {
    let id: Int
    let name: String
    let state: String
}

enum WoodpeckerTime {
    /// Unix seconds, with 0 for never.
    static func date(_ seconds: Int?) -> Date? {
        seconds.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
    }
}
