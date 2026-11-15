import FP

extension GitHubService {
    public func scope(for query: StatusQuery) async -> Result<MonitorScope, RunnersError> {
        switch query.target {
            case .authenticatedUser:
                await api.authenticatedUser()
                    .flatMapAsync { me in
                        await ownedScope(of: me, listing: .authenticatedUser, query: query)
                    }

            case .owner(let login):
                await ownerListing(login)
                    .flatMapAsync { owner, listing in
                        await ownedScope(of: owner, listing: listing, query: query)
                    }

            case .repositories(let names):
                await repositories(names, concurrency: query.concurrency)
                    .map { MonitorScope(owner: nil, repositories: $0) }
        }
    }

    /// The owner, and the listing that sees the most of its repositories with this token.
    func ownerListing(_ login: String) async -> Result<(GitHubAccount, GitHubListing), RunnersError>
    {
        let api = api
        return await withAll(await api.account(login), await api.authenticatedUser())
            .map { owner, viewer in (owner, GitHubListing.of(owner, viewer: viewer)) }
    }

    func ownedScope(
        of owner: GitHubAccount,
        listing: GitHubListing,
        query: StatusQuery
    ) async -> Result<MonitorScope, RunnersError> {
        await api.repositories(listing)
            .map { $0.filter { $0.canRunWorkflows(includingForks: query.includeForks) } }
            .map { MonitorScope(owner: owner.owner, repositories: $0.map(\.repository)) }
    }

    func repositories(
        _ names: [String],
        concurrency: Int
    ) async -> Result<[Repository], RunnersError> {
        let api = api
        return await names.traverseAsync(concurrency: concurrency) { name in
            await api.repository(name).map(\.repository)
        }
    }
}
