/// A CI service whose runs can be monitored.
public enum Provider: String, Codable, Sendable, CaseIterable {
    case github
    case gitlab

    public var name: String {
        switch self {
            case .github: "GitHub"
            case .gitlab: "GitLab"
        }
    }

    /// What the service calls a repository.
    public var repositoryTerm: (singular: String, plural: String) {
        switch self {
            case .github: ("repository", "repositories")
            case .gitlab: ("project", "projects")
        }
    }
}
