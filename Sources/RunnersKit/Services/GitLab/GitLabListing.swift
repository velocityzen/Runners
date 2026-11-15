import Foundation

/// Where to list a namespace's projects. Archived ones are left out by GitLab.
enum GitLabListing: Sendable, Equatable {
    /// Projects the token's user owns.
    case owned
    /// A group's projects, its subgroups' included.
    case group(Int)
    /// A user's projects that the token can see.
    case user(Int)

    var path: [String] {
        switch self {
            case .owned: ["projects"]
            case .group(let id): ["groups", String(id), "projects"]
            case .user(let id): ["users", String(id), "projects"]
        }
    }

    var query: [URLQueryItem] {
        let scope: [URLQueryItem] =
            switch self {
                case .owned: [URLQueryItem(name: "owned", value: "true")]
                case .group: [URLQueryItem(name: "include_subgroups", value: "true")]
                case .user: []
            }
        return scope + [URLQueryItem(name: "archived", value: "false"), .perPage]
    }
}
