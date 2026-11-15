import Foundation

/// A repository, with the fields that decide whether its workflows can run.
public struct Repository: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let owner: Account
    public let isPrivate: Bool
    public let isFork: Bool
    public let isArchived: Bool
    public let isDisabled: Bool?
    public let htmlURL: URL
    public let pushedAt: Date?

    public init(
        id: Int,
        name: String,
        fullName: String,
        owner: Account,
        isPrivate: Bool = false,
        isFork: Bool = false,
        isArchived: Bool = false,
        isDisabled: Bool? = false,
        htmlURL: URL,
        pushedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.owner = owner
        self.isPrivate = isPrivate
        self.isFork = isFork
        self.isArchived = isArchived
        self.isDisabled = isDisabled
        self.htmlURL = htmlURL
        self.pushedAt = pushedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, owner
        case fullName = "full_name"
        case isPrivate = "private"
        case isFork = "fork"
        case isArchived = "archived"
        case isDisabled = "disabled"
        case htmlURL = "html_url"
        case pushedAt = "pushed_at"
    }

    /// Archived and disabled repositories cannot run workflows; forks rarely do.
    public func canRunWorkflows(includingForks: Bool) -> Bool {
        !isArchived && isDisabled != true && (includingForks || !isFork)
    }
}
