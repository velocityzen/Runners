import Foundation

/// The runners a service lists for a query's target, and what it had to leave out.
public struct RunnerListing: Sendable, Hashable {
    /// `nil` for an explicit list of repositories.
    public let owner: Owner?
    public let runners: [Runner]
    /// What was left out and why, such as runners the token may not list.
    public let notes: [String]

    public init(owner: Owner?, runners: [Runner], notes: [String] = []) {
        self.owner = owner
        self.runners = runners
        self.notes = notes
    }
}

/// The runners of an owner or of some repositories when the snapshot was taken.
public struct RunnersSnapshot: Encodable, Sendable, Equatable {
    public let provider: any Provider
    public let owner: Owner?
    /// Busy first, then idle, paused and offline; by name within each.
    public let runners: [Runner]
    public let notes: [String]
    public let rateLimit: RateLimit?
    public let fetchedAt: Date

    public init(
        provider: any Provider,
        listing: RunnerListing,
        rateLimit: RateLimit?,
        fetchedAt: Date
    ) {
        self.provider = provider
        self.owner = listing.owner
        self.runners = Self.ordered(listing.runners)
        self.notes = listing.notes
        self.rateLimit = rateLimit
        self.fetchedAt = fetchedAt
    }

    static func ordered(_ runners: [Runner]) -> [Runner] {
        runners.sorted { lhs, rhs in
            guard lhs.state == rhs.state else { return lhs.state < rhs.state }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }

    /// Providers are told apart by ``Provider/id``.
    public static func == (lhs: RunnersSnapshot, rhs: RunnersSnapshot) -> Bool {
        lhs.provider.id == rhs.provider.id && lhs.owner == rhs.owner
            && lhs.runners == rhs.runners && lhs.notes == rhs.notes
            && lhs.rateLimit == rhs.rateLimit && lhs.fetchedAt == rhs.fetchedAt
    }

    enum CodingKeys: String, CodingKey {
        case provider, owner, runners, notes
        case rateLimit = "rate_limit"
        case fetchedAt = "fetched_at"
    }

    /// The provider as its ``Provider/id``.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider.id, forKey: .provider)
        try container.encodeIfPresent(owner, forKey: .owner)
        try container.encode(runners, forKey: .runners)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(rateLimit, forKey: .rateLimit)
        try container.encode(fetchedAt, forKey: .fetchedAt)
    }

    public func json() -> Result<String, RunnersError> {
        JSONCoding.encode(self)
    }
}

/// The runners in one state.
public struct RunnerGroup: Sendable, Hashable {
    public let state: Runner.State
    public let runners: [Runner]
}

extension RunnersSnapshot {
    /// In state order, leaving out states no runner is in.
    public var byState: [RunnerGroup] {
        Runner.State.allCases.compactMap { state in
            let runners = runners.filter { $0.state == state }
            return runners.isEmpty ? nil : RunnerGroup(state: state, runners: runners)
        }
    }

    /// `acme on GitHub`
    public var scope: String {
        owner.map { "\($0.login) on \(provider.name)" } ?? provider.name
    }

    /// `5 runners, 2 busy`, or `no runners`.
    public var summary: String {
        guard !runners.isEmpty else { return "no runners" }
        let busy = runners.count { $0.state == .busy }
        let total = counted(runners.count, "runner")
        return busy == 0 ? total : "\(total), \(busy) busy"
    }
}
