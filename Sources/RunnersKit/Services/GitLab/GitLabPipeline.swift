import Foundation

/// A pipeline as `GET /projects/{id}/pipelines/{pipeline_id}` reports it.
struct GitLabPipeline: Codable, Sendable, Hashable {
    let id: Int
    let iid: Int?
    let name: String?
    let status: String
    /// What started it: `push`, `schedule`, `merge_request_event`, `web`, …
    let source: String?
    let ref: String?
    let sha: String?
    let webURL: URL
    let createdAt: Date
    let startedAt: Date?
    let user: GitLabUser?

    enum CodingKeys: String, CodingKey {
        case id, iid, name, status, source, ref, sha, user
        case webURL = "web_url"
        case createdAt = "created_at"
        case startedAt = "started_at"
    }

    /// The commit title is not part of a pipeline; it comes from one of its jobs.
    func run(title: String?, actor: String?) -> Run {
        Run(
            id: String(id),
            name: name ?? "Pipeline",
            title: title,
            number: iid,
            trigger: source,
            status: RunStatus(gitLab: status),
            conclusion: Conclusion(gitLab: status),
            branch: ref,
            commit: sha,
            webURL: webURL,
            createdAt: createdAt,
            startedAt: startedAt,
            actor: user?.username ?? actor
        )
    }
}
