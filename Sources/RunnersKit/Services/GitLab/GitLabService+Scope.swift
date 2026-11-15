import FP

extension GitLabService {
    public func scope(for query: StatusQuery) async -> Result<MonitorScope, RunnersError> {
        switch query.target {
            case .authenticatedUser:
                await api.currentUser()
                    .flatMapAsync { me in
                        await ownedScope(of: me.owner, listing: .owned, query: query)
                    }

            case .owner(let path):
                await namespace(path)
                    .flatMapAsync { owner, listing in
                        await ownedScope(of: owner, listing: listing, query: query)
                    }

            case .repositories(let paths):
                await projects(paths, concurrency: query.concurrency)
                    .map { MonitorScope(owner: nil, repositories: $0) }
        }
    }

    /// A group by full path or else a user by username, and where to list its projects.
    func namespace(_ path: String) async -> Result<(Owner, GitLabListing), RunnersError> {
        await api.group(path)
            .map { ($0.owner, GitLabListing.group($0.id)) }
            .orElseAsync { error in await user(path, after: error) }
    }

    /// The user named `username`, when looking for a group of that name found none.
    func user(
        _ username: String,
        after error: RunnersError
    ) async -> Result<(Owner, GitLabListing), RunnersError> {
        guard case .notFound = error else { return .failure(error) }
        return await api.users(named: username)
            .flatMap {
                .fromOptional(
                    $0.first,
                    error: .notFound("no GitLab group or user named \(username)")
                )
            }
            .map { ($0.owner, GitLabListing.user($0.id)) }
    }

    func ownedScope(
        of owner: Owner,
        listing: GitLabListing,
        query: StatusQuery
    ) async -> Result<MonitorScope, RunnersError> {
        await api.projects(listing)
            .map { $0.filter { $0.canRunPipelines(includingForks: query.includeForks) } }
            .map { MonitorScope(owner: owner, repositories: $0.map(\.repository)) }
    }

    func projects(_ paths: [String], concurrency: Int) async -> Result<[Repository], RunnersError> {
        let api = api
        return await paths.traverseAsync(concurrency: concurrency) { path in
            await api.project(path).map(\.repository)
        }
    }
}
