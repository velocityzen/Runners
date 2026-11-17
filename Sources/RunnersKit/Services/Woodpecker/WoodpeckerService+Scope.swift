import FP

extension WoodpeckerService {
    public func scope(for query: StatusQuery) async -> Result<MonitorScope, RunnersError> {
        switch query.target {
            case .authenticatedUser:
                guard !isAnonymous else { return .failure(Self.noToken) }
                let api = api
                return await withAll(await api.authenticatedUser(), await api.repositories())
                    .map { me, repositories in scope(of: me.owner, repositories) }

            case .owner(let name):
                guard !isAnonymous else { return .failure(Self.noToken) }
                return await api.repositories()
                    .map { $0.filter { $0.owner.lowercased() == name.lowercased() } }
                    .flatMap { repositories in
                        guard let first = repositories.first else {
                            return .failure(
                                .notFound("none of your Woodpecker repositories belong to \(name)")
                            )
                        }
                        let owner = Owner(id: first.owner, login: first.owner, kind: .unknown)
                        return .success(scope(of: owner, repositories))
                    }

            case .repositories(let names):
                let api = api
                let isAnonymous = isAnonymous
                return await names.traverseAsync(concurrency: query.concurrency) { name in
                    await api.repository(name)
                        .mapError { Self.lookupError($0, name: name, isAnonymous: isAnonymous) }
                        .map { $0.repository(server: api.server) }
                }
                .map { MonitorScope(owner: nil, repositories: $0) }
        }
    }

    /// The active repositories that have run a pipeline, counting the rest.
    func scope(of owner: Owner, _ repositories: [WoodpeckerRepository]) -> MonitorScope {
        let active = repositories.filter { $0.active != false }
        return MonitorScope(
            owner: owner,
            repositories: active.filter { $0.lastPipeline != nil }
                .map { $0.repository(server: api.server) },
            repositoryCount: active.count
        )
    }

    /// Without a token, Woodpecker answers 401 for a repository that doesn't exist or isn't
    /// public, not 404.
    static func lookupError(
        _ error: RunnersError,
        name: String,
        isAnonymous: Bool
    ) -> RunnersError {
        guard isAnonymous, case .unauthorized = error else { return error }
        return .notFound(
            "no public Woodpecker repository named \(name); a private one needs WOODPECKER_TOKEN"
        )
    }

    static let noToken = RunnersError.tokenUnavailable(
        "set WOODPECKER_TOKEN to a personal access token from your user page on the Woodpecker "
            + "server (not your Codeberg token), or name public repositories with --repo"
    )
}
