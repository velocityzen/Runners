import FP

/// The repositories to check, and whose they are.
struct MonitorScope: Sendable {
    let owner: Account?
    let repositories: [Repository]
}

extension ActionsMonitor {
    func scope(for query: StatusQuery) async -> Result<MonitorScope, GitHubError> {
        switch query.target {
            case .authenticatedUser:
                await client.authenticatedUser()
                    .flatMapAsync { me in await ownedScope(of: me, listing: .authenticatedUser, query: query) }

            case .owner(let login):
                await ownerListing(login)
                    .flatMapAsync { owner, listing in await ownedScope(of: owner, listing: listing, query: query) }

            case .repositories(let names):
                await repositories(names, concurrency: query.concurrency)
                    .map { MonitorScope(owner: nil, repositories: $0) }
        }
    }

    /// The owner, and the listing that sees the most of its repositories with this token.
    func ownerListing(_ login: String) async -> Result<(Account, RepositoryListing), GitHubError> {
        let client = client
        return await withAll(await client.account(login), await client.authenticatedUser())
            .map { owner, viewer in (owner, RepositoryListing.of(owner, viewer: viewer)) }
    }

    func ownedScope(
        of owner: Account,
        listing: RepositoryListing,
        query: StatusQuery
    ) async -> Result<MonitorScope, GitHubError> {
        await client.repositories(listing)
            .map { $0.filter { $0.canRunWorkflows(includingForks: query.includeForks) } }
            .map { MonitorScope(owner: owner, repositories: $0) }
    }

    func repositories(_ names: [String], concurrency: Int) async -> Result<[Repository], GitHubError> {
        let client = client
        return await names.traverseAsync(concurrency: concurrency) { name in
            await client.repository(name)
        }
    }
}
