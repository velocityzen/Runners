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
                    .flatMapAsync { await withWorkflows($0, owner: nil, query: query) }
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
            .flatMapAsync {
                await withWorkflows($0.map(\.repository), owner: owner.owner, query: query)
            }
    }

    /// The scope of the repositories that have workflows, counting all of them.
    func withWorkflows(
        _ repositories: [Repository],
        owner: Owner?,
        query: StatusQuery
    ) async -> Result<MonitorScope, RunnersError> {
        let api = api
        return await repositories.traverseAsync(concurrency: query.concurrency) { repository in
            await api.ifHasWorkflows(repository)
        }
        .map { found in
            MonitorScope(
                owner: owner,
                repositories: found.compact(),
                repositoryCount: repositories.count
            )
        }
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
