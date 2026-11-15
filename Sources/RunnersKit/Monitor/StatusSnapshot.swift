import Foundation

/// The runs that had not finished when the snapshot was taken. A watch adds the runs it saw
/// finish, with how they ended.
public struct StatusSnapshot: Encodable, Sendable, Equatable {
    public let provider: any Provider
    /// The account whose repositories were checked; `nil` for an explicit repository list.
    public let owner: Owner?
    public let repositoryCount: Int
    /// Grouped by repository name, newest run first.
    public let runs: [ActiveRun]
    /// `nil` when the service does not report one.
    public let rateLimit: RateLimit?
    public let fetchedAt: Date

    public init(
        provider: any Provider,
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

    func with(runs: [ActiveRun]) -> StatusSnapshot {
        StatusSnapshot(
            provider: provider,
            owner: owner,
            repositoryCount: repositoryCount,
            runs: runs,
            rateLimit: rateLimit,
            fetchedAt: fetchedAt
        )
    }

    /// Providers are told apart by ``Provider/id``.
    public static func == (lhs: StatusSnapshot, rhs: StatusSnapshot) -> Bool {
        lhs.provider.id == rhs.provider.id && lhs.owner == rhs.owner
            && lhs.repositoryCount == rhs.repositoryCount && lhs.runs == rhs.runs
            && lhs.rateLimit == rhs.rateLimit && lhs.fetchedAt == rhs.fetchedAt
    }

    enum CodingKeys: String, CodingKey {
        case provider, owner, runs
        case repositoryCount = "repository_count"
        case rateLimit = "rate_limit"
        case fetchedAt = "fetched_at"
    }

    /// The provider as its ``Provider/id``.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider.id, forKey: .provider)
        try container.encodeIfPresent(owner, forKey: .owner)
        try container.encode(repositoryCount, forKey: .repositoryCount)
        try container.encode(runs, forKey: .runs)
        try container.encodeIfPresent(rateLimit, forKey: .rateLimit)
        try container.encode(fetchedAt, forKey: .fetchedAt)
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
