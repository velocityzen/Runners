/// A user or an organization that owns repositories: a GitHub account, a GitLab user or group.
public struct Owner: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case user
        /// A GitHub organization or a GitLab group.
        case organization
        case bot
        case unknown
    }

    public let id: String
    /// The handle: a GitHub login, a GitLab username or group path.
    public let login: String
    public let kind: Kind

    public init(id: String, login: String, kind: Kind) {
        self.id = id
        self.login = login
        self.kind = kind
    }

    /// Logins are case-insensitive.
    public func isSame(as other: Owner) -> Bool {
        login.lowercased() == other.login.lowercased()
    }
}
