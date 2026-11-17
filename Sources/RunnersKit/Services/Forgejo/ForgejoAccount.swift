import Foundation

/// `GET /user`, `GET /users/{name}`, and the `owner` of a repository.
struct ForgejoAccount: Codable, Sendable, Hashable {
    let id: Int
    let login: String

    func owner(kind: Owner.Kind) -> Owner {
        Owner(id: String(id), login: login, kind: kind)
    }
}

/// `GET /orgs/{org}`
struct ForgejoOrganization: Codable, Sendable, Hashable {
    let id: Int
    /// The org's login.
    let username: String

    var owner: Owner {
        Owner(id: String(id), login: username, kind: .organization)
    }
}

/// A repository from `GET /repos/{owner}/{repo}` or a repository list.
struct ForgejoRepository: Codable, Sendable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let owner: ForgejoAccount
    let htmlURL: URL
    let isPrivate: Bool
    let isFork: Bool
    let isArchived: Bool
    let isMirror: Bool?
    let isEmpty: Bool?
    /// Whether Actions is turned on for it.
    let hasActions: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, owner
        case fullName = "full_name"
        case htmlURL = "html_url"
        case isPrivate = "private"
        case isFork = "fork"
        case isArchived = "archived"
        case isMirror = "mirror"
        case isEmpty = "empty"
        case hasActions = "has_actions"
    }

    /// Archived, empty and mirrored repositories run nothing, nor do ones with Actions off.
    func canRunActions(includingForks: Bool) -> Bool {
        hasActions != false && !isArchived && isEmpty != true && isMirror != true
            && (includingForks || !isFork)
    }

    var repository: Repository {
        Repository(
            id: String(id),
            name: name,
            fullName: fullName,
            webURL: htmlURL,
            isPrivate: isPrivate,
            isFork: isFork,
            isArchived: isArchived
        )
    }
}
