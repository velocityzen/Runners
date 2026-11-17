import FP

extension GitLabService {
    /// The runners the token's user can manage; a group's, with those of the groups above it;
    /// for another user or some projects, each project's. A busy runner is read once more for
    /// the jobs it is on.
    ///
    /// Groups and projects can also use the instance's runners, which on GitLab.com are
    /// GitLab's own, so those are left out, and the listing says how many.
    public func runners(for query: StatusQuery) async -> Result<RunnerListing, RunnersError> {
        switch query.target {
            case .authenticatedUser:
                await withAll(await api.currentUser(), await api.runners(["runners"]))
                    .mapAsync { me, runners in
                        RunnerListing(
                            owner: me.owner,
                            runners: await withJobs(runners, query: query)
                        )
                    }

            case .owner(let path):
                await namespace(path)
                    .flatMapAsync { owner, listing in
                        guard case .group(let id) = listing else {
                            return await api.projects(listing)
                                .map {
                                    $0.filter {
                                        $0.canRunPipelines(includingForks: query.includeForks)
                                    }
                                }
                                .flatMapAsync { projects in
                                    await runners(
                                        in: projects.map(\.repository),
                                        owner: owner,
                                        query: query
                                    )
                                }
                        }
                        return await groupRunners(id, owner: owner, query: query)
                    }

            case .repositories(let paths):
                await projects(paths, concurrency: query.concurrency)
                    .flatMapAsync { await runners(in: $0, owner: nil, query: query) }
        }
    }

    func groupRunners(
        _ id: Int,
        owner: Owner,
        query: StatusQuery
    ) async -> Result<RunnerListing, RunnersError> {
        await api.runners(["groups", String(id), "runners"])
            .mapError { error in
                guard case .forbidden(let message) = error else { return error }
                return .forbidden(
                    "\(message); listing a group's runners takes the Owner role in the group "
                        + "and a token with the manage_runner scope."
                )
            }
            .mapAsync { runners in await listing(owner, runners, query: query) }
    }

    /// Each project's runners. Listing them takes the Maintainer role, so projects where the
    /// token's user has less are left out, and the listing says how many.
    func runners(
        in projects: [Repository],
        owner: Owner?,
        query: StatusQuery
    ) async -> Result<RunnerListing, RunnersError> {
        let api = api
        return await projects.traverseAsync(concurrency: query.concurrency) { project in
            await api.runners(["projects", project.id, "runners"])
                .map(Optional.some)
                .orElse { error in
                    guard case .forbidden = error else { return .failure(error) }
                    return .success(nil)
                }
        }
        .mapAsync { found in
            let denied = found.count { $0 == nil }
            let note =
                "Runners of \(denied) of \(projects.count) projects left out: "
                + "listing them takes the Maintainer role."
            let listed = await listing(
                owner,
                found.compact().flatMap { $0 }.uniqued(by: \.id),
                query: query
            )
            return RunnerListing(
                owner: owner,
                runners: listed.runners,
                notes: (denied > 0 ? [note] : []) + listed.notes
            )
        }
    }

    /// The runners without the instance's, with the jobs of those that are busy.
    func listing(
        _ owner: Owner?,
        _ runners: [GitLabRunner],
        query: StatusQuery
    ) async -> RunnerListing {
        let own = runners.filter { $0.kind != .instance }
        let shared = runners.count - own.count
        let note =
            "\(counted(shared, "instance runner")) left out: they belong to the instance, "
            + "not to \(owner?.login ?? "these projects")."
        return RunnerListing(
            owner: owner,
            runners: await withJobs(own, query: query),
            notes: shared > 0 ? [note] : []
        )
    }

    /// Asks only for the jobs of runners that say they are busy. A job list the token can't
    /// read leaves the runner without jobs rather than failing.
    func withJobs(_ runners: [GitLabRunner], query: StatusQuery) async -> [Runner] {
        let api = api
        return await runners.traverseAsync(concurrency: query.concurrency) { runner in
            guard runner.isBusy == true else {
                return Result<Runner, Never>.success(runner.runner())
            }
            let jobs = await api.runningJobs(of: runner.id).map { $0.map(\.job) }.getOrElse([])
            return .success(runner.runner(jobs: jobs))
        }
        .get()
    }
}
