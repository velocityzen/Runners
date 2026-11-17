import FP
import FPPipe

extension ForgejoService {
    /// One request per repository for its unfinished runs, whatever their statuses, then one
    /// per run for its jobs and one per running job for its steps.
    ///
    /// Forgejo's `…/actions/runners/jobs` would find the repositories with active jobs in one
    /// call, but it lists only jobs waiting for a runner or running, so it would miss runs
    /// that wait for approval, and it needs an admin's token.
    public func activeRuns(
        in repositories: [Repository],
        query: StatusQuery
    ) async -> Result<[ActiveRun], RunnersError> {
        let api = api
        let statuses = Array(Set(query.statuses.flatMap(\.forgejoQueryValues))).sorted()
        guard !statuses.isEmpty else { return .success([]) }
        return await Pipe<ActiveRun, RunnersError> {
            From(repositories)
            AsyncFlatMap(concurrency: query.concurrency) { (repository: Repository) in
                await api.runs(in: repository.fullName, statuses: statuses)
                    .map { runs in
                        runs.map { ActiveRun(repository: repository, run: $0.run) }
                            .filter { query.statuses.contains($0.run.status) }
                    }
            }
            FlatMapSequence { (runs: [ActiveRun]) in runs }
            if query.includeJobs {
                AsyncFlatMap(concurrency: query.concurrency) { (run: ActiveRun) in
                    await api.withJobs(run, concurrency: query.concurrency)
                }
            }
        }
        .toResult()
    }

    public func latest(_ run: ActiveRun, query: StatusQuery) async -> Result<
        ActiveRun, RunnersError
    > {
        let api = api
        return await api.run(in: run.repository.fullName, id: run.run.id)
            .map { ActiveRun(repository: run.repository, run: $0.run) }
            .flatMapAsync { run in
                query.includeJobs
                    ? await api.withJobs(run, concurrency: query.concurrency) : .success(run)
            }
    }
}

extension ForgejoAPI {
    /// The run's jobs, each running one read again for its steps: when it started and the step
    /// it is on. A job that can't be read again keeps what the list said.
    func withJobs(_ active: ActiveRun, concurrency: Int) async -> Result<ActiveRun, RunnersError> {
        let repository = active.repository.fullName
        return await jobs(in: repository, runID: active.run.id)
            .mapAsync { listed in
                await listed.traverseAsync(concurrency: concurrency) { job in
                    guard job.status == "running" else {
                        return Result<ForgejoJob, Never>.success(job)
                    }
                    return .success(await self.job(in: repository, id: job.id).getOrElse(job))
                }
                .get()
            }
            .map { jobs in active.with(jobs: jobs.map { $0.job(createdAt: active.run.createdAt) }) }
    }
}
