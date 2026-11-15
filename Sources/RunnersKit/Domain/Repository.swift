import Foundation

/// A repository (a GitLab project) that can run CI.
public struct Repository: Codable, Sendable, Hashable, Identifiable {
    /// The service's own ID.
    public let id: String
    public let name: String
    /// `owner/name`; on GitLab `group/subgroup/name`.
    public let fullName: String
    public let webURL: URL
    public let isPrivate: Bool
    public let isFork: Bool
    public let isArchived: Bool

    public init(
        id: String,
        name: String,
        fullName: String,
        webURL: URL,
        isPrivate: Bool = false,
        isFork: Bool = false,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.webURL = webURL
        self.isPrivate = isPrivate
        self.isFork = isFork
        self.isArchived = isArchived
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case fullName = "full_name"
        case webURL = "web_url"
        case isPrivate = "is_private"
        case isFork = "is_fork"
        case isArchived = "is_archived"
    }
}
