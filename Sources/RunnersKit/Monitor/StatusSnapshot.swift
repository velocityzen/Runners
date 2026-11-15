import Foundation

/// The runs that had not finished when the snapshot was taken.
public struct StatusSnapshot: Codable, Sendable, Hashable {
    public let provider: Provider
    /// The account whose repositories were checked; `nil` for an explicit repository list.
    public let owner: Owner?
    public let repositoryCount: Int
    /// Grouped by repository name, newest run first.
    public let runs: [ActiveRun]
    /// `nil` when the service does not report one.
    public let rateLimit: RateLimit?
    public let fetchedAt: Date

    public init(
        provider: Provider,
        owner: Owner?,
        repositoryCount: Int,
        runs: [ActiveRun],
        rateLimit: RateLimit?,
        fetchedAt: Date
    ) {
        self.provider = provider
        self.owner = owner
        self.repositoryCount = repositoryCount
        self.runs = runs
        self.rateLimit = rateLimit
        self.fetchedAt = fetchedAt
    }

    enum CodingKeys: String, CodingKey {
        case provider, owner, runs
        case repositoryCount = "repository_count"
        case rateLimit = "rate_limit"
        case fetchedAt = "fetched_at"
    }
}

/// The active runs of one repository.
public struct RepositoryRuns: Sendable, Hashable {
    public let repository: Repository
    public let runs: [ActiveRun]
}

public extension StatusSnapshot {
    var byRepository: [RepositoryRuns] {
        runs.reduce(into: []) { groups, run in
            guard let last = groups.last, last.repository.id == run.repository.id else {
                groups.append(RepositoryRuns(repository: run.repository, runs: [run]))
                return
            }
            groups[groups.count - 1] = RepositoryRuns(
                repository: last.repository,
                runs: last.runs + [run]
            )
        }
    }

    func json() -> Result<String, RunnersError> {
        JSONCoding.encode(self)
    }
}
