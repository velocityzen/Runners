import FP

extension ForgejoService {
    public func scope(for query: StatusQuery) async -> Result<MonitorScope, RunnersError> {
        switch query.target {
            case .authenticatedUser:
                guard !isAnonymous else {
                    return .failure(
                        .tokenUnavailable(
                            "set FORGEJO_TOKEN (or CODEBERG_TOKEN) to a personal access token, "
                                + "or name an owner to see their public repositories"
                        )
                    )
                }
                return await api.authenticatedUser()
                    .flatMapAsync { me in
                        let owner = me.owner(kind: .user)
                        return await ownedScope(of: owner, path: ["user", "repos"], query: query)
                    }

            case .owner(let name):
                return await namespace(name)
                    .flatMapAsync { owner, path in
                        await ownedScope(of: owner, path: path, query: query)
                    }

            case .repositories(let names):
                let api = api
                return await names.traverseAsync(concurrency: query.concurrency) { name in
                    await api.repository(name).map(\.repository)
                }
                .map { MonitorScope(owner: nil, repositories: $0) }
        }
    }

    /// An organization by name or else a user, and where to list its repositories.
    func namespace(_ name: String) async -> Result<(Owner, [String]), RunnersError> {
        await api.organization(name)
            .map { ($0.owner, ["orgs", name, "repos"]) }
            .orElseAsync { error in
                guard case .notFound = error else { return .failure(error) }
                return await api.user(name)
                    .mapError { error in
                        guard case .notFound = error else { return error }
                        return .notFound("no Forgejo organization or user named \(name)")
                    }
                    .map { ($0.owner(kind: .user), ["users", name, "repos"]) }
            }
    }

    /// The owner's repositories that can run Actions. `/user/repos` lists every repository
    /// the user can reach, so it keeps only the user's own.
    func ownedScope(
        of owner: Owner,
        path: [String],
        query: StatusQuery
    ) async -> Result<MonitorScope, RunnersError> {
        await api.repositories(path)
            .map { repositories in
                let owned = repositories.filter { $0.owner.login == owner.login }
                return MonitorScope(
                    owner: owner,
                    repositories:
                        owned
                        .filter { $0.canRunActions(includingForks: query.includeForks) }
                        .map(\.repository),
                    repositoryCount: owned.count
                )
            }
    }
}
