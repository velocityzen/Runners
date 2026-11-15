import Foundation

/// Where to list an account's repositories.
enum GitHubListing: Sendable, Equatable {
    /// Repositories the token's user owns, private ones included.
    case authenticatedUser
    case organization(String)
    /// Another user's public repositories.
    case user(String)

    /// The listing that sees the most of `owner`'s repositories as `viewer`.
    static func of(_ owner: GitHubAccount, viewer: GitHubAccount) -> GitHubListing {
        if owner.type == "Organization" { return .organization(owner.login) }
        return owner.login.lowercased() == viewer.login.lowercased()
            ? .authenticatedUser : .user(owner.login)
    }

    var path: [String] {
        switch self {
            case .authenticatedUser: ["user", "repos"]
            case .organization(let login): ["orgs", login, "repos"]
            case .user(let login): ["users", login, "repos"]
        }
    }

    var query: [URLQueryItem] {
        let filter =
            switch self {
                case .authenticatedUser: URLQueryItem(name: "affiliation", value: "owner")
                case .organization: URLQueryItem(name: "type", value: "all")
                case .user: URLQueryItem(name: "type", value: "owner")
            }
        return [filter, .perPage]
    }
}
