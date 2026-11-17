import FP

extension GitHubService {
    /// An organization's self-hosted runners and pools of larger runners; for a user or some
    /// repositories, each repository's own runners.
    public func runners(for query: StatusQuery) async -> Result<RunnerListing, RunnersError> {
        switch query.target {
            case .authenticatedUser:
                await api.authenticatedUser()
                    .flatMapAsync { me in
                        await repositoryRunners(of: me, listing: .authenticatedUser, query: query)
                    }

            case .owner(let login):
                await ownerListing(login)
                    .flatMapAsync { owner, listing in
                        owner.kind == .organization
                            ? await organizationRunners(owner)
                            : await repositoryRunners(of: owner, listing: listing, query: query)
                    }

            case .repositories(let names):
                await repositories(names, concurrency: query.concurrency)
                    .flatMapAsync { await runners(in: $0, owner: nil, query: query) }
        }
    }

    /// The organization's runners, which include those of its repositories, and its larger
    /// runners. Those need the `manage_runners:org` scope, so without it the listing says
    /// they are left out rather than failing.
    func organizationRunners(_ organization: GitHubAccount) async -> Result<
        RunnerListing, RunnersError
    > {
        let api = api
        let login = organization.login
        return await withAll(
            await api.runners(ofOrganization: login),
            .success(Self.hosted(await api.hostedRunners(ofOrganization: login)))
        )
        .map { selfHosted, hosted in
            RunnerListing(
                owner: organization.owner,
                runners: selfHosted.map(\.runner) + hosted.runners,
                notes: hosted.note.map { [$0] } ?? []
            )
        }
    }

    /// No pools when the organization has none, which GitHub answers with 404.
    static func hosted(
        _ result: Result<[GitHubHostedRunner], RunnersError>
    ) -> (runners: [Runner], note: String?) {
        result.match(
            { (runners: $0.map(\.runner), note: nil) },
            { error in
                if case .notFound = error { return (runners: [], note: nil) }
                return (
                    runners: [],
                    note: "Larger GitHub-hosted runners left out: \(error.localizedDescription)"
                )
            }
        )
    }

    func repositoryRunners(
        of owner: GitHubAccount,
        listing: GitHubListing,
        query: StatusQuery
    ) async -> Result<RunnerListing, RunnersError> {
        await api.repositories(listing)
            .map { $0.filter { $0.canRunWorkflows(includingForks: query.includeForks) } }
            .flatMapAsync {
                await runners(in: $0.map(\.repository), owner: owner.owner, query: query)
            }
    }

    /// Each repository's own runners. Listing them takes admin access to the repository, so
    /// those the token can't administer are left out, and the listing says how many.
    func runners(
        in repositories: [Repository],
        owner: Owner?,
        query: StatusQuery
    ) async -> Result<RunnerListing, RunnersError> {
        let api = api
        return await repositories.traverseAsync(concurrency: query.concurrency) { repository in
            await api.runners(in: repository.fullName)
                .map(Optional.some)
                .orElse { error in Self.isDenied(error) ? .success(nil) : .failure(error) }
        }
        .map { found in
            let denied = found.count { $0 == nil }
            let note =
                "Runners of \(denied) of \(repositories.count) repositories left out: "
                + "listing them takes admin access to the repository."
            return RunnerListing(
                owner: owner,
                runners: found.compact().flatMap { $0 }.map(\.runner).uniqued(by: \.id),
                notes: denied > 0 ? [note] : []
            )
        }
    }

    /// GitHub answers 404 as well as 403 for a repository's runners without admin access.
    static func isDenied(_ error: RunnersError) -> Bool {
        switch error {
            case .forbidden, .notFound: true
            default: false
        }
    }
}
