import Foundation

/// A project as GitLab lists it.
struct GitLabProject: Codable, Sendable, Hashable {
    /// Present only on forks.
    struct ForkParent: Codable, Sendable, Hashable {
        let id: Int
    }

    let id: Int
    let name: String
    let pathWithNamespace: String
    let webURL: URL
    /// `private`, `internal` or `public`.
    let visibility: String?
    let archived: Bool?
    /// `enabled`, `private` or `disabled`.
    let buildsAccessLevel: String?
    let forkedFromProject: ForkParent?

    enum CodingKeys: String, CodingKey {
        case id, name, visibility, archived
        case pathWithNamespace = "path_with_namespace"
        case webURL = "web_url"
        case buildsAccessLevel = "builds_access_level"
        case forkedFromProject = "forked_from_project"
    }

    /// Archived projects and projects with CI/CD turned off cannot run pipelines; forks rarely do.
    func canRunPipelines(includingForks: Bool) -> Bool {
        archived != true && buildsAccessLevel != "disabled"
            && (includingForks || forkedFromProject == nil)
    }

    var repository: Repository {
        Repository(
            id: String(id),
            name: name,
            fullName: pathWithNamespace,
            webURL: webURL,
            isPrivate: visibility != "public",
            isFork: forkedFromProject != nil,
            isArchived: archived ?? false
        )
    }
}
