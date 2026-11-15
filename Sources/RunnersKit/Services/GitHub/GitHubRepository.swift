import Foundation

/// A repository as GitHub lists it.
struct GitHubRepository: Codable, Sendable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let owner: GitHubAccount
    let isPrivate: Bool
    let isFork: Bool
    let isArchived: Bool
    let isDisabled: Bool?
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case id, name, owner
        case fullName = "full_name"
        case isPrivate = "private"
        case isFork = "fork"
        case isArchived = "archived"
        case isDisabled = "disabled"
        case htmlURL = "html_url"
    }

    /// Archived and disabled repositories cannot run workflows; forks rarely do.
    func canRunWorkflows(includingForks: Bool) -> Bool {
        !isArchived && isDisabled != true && (includingForks || !isFork)
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
