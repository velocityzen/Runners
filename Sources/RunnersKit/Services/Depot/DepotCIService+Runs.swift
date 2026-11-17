import FP

/// A run `ListRuns` gave, with the repository of the scope it is for.
struct DepotListedRun: Sendable {
    let run: DepotRun
    let repository: Repository
}

/// A workflow to show, with the repository it is for and its jobs' statuses.
struct DepotActiveWorkflow: Sendable {
    let workflow: DepotWorkflowRun
    let repository: Repository
    let jobs: [DepotJobStatus]
}

extension DepotCIService {
    /// One `ListRuns` for the organization, kept to the scope's repositories, or one per
    /// repository named with `--repo`; then `GetRunStatus` per run for its workflows, and,
    /// with jobs, `GetJob` per unfinished job for its times and the machine it asks for.
    public func activeRuns(
        in repositories: [Repository],
        query: StatusQuery
    ) async -> Result<[ActiveRun], RunnersError> {
        let statuses = DepotRun.statuses.filter { status in
            query.statuses.contains { $0.depotQueryValue == status }
        }
        // An empty status list would ask for Depot's default, not for none.
        guard !statuses.isEmpty, !repositories.isEmpty else { return .success([]) }
        return await listed(in: repositories, statuses: statuses, query: query)
            .flatMapAsync { runs in await workflows(of: runs, query: query) }
            .flatMapAsync { workflows in await activeRuns(workflows, query: query) }
    }

    func listed(
        in repositories: [Repository],
        statuses: [String],
        query: StatusQuery
    ) async -> Result<[DepotListedRun], RunnersError> {
        let api = api
        guard case .repositories = query.target else {
            let byName = Dictionary(
                repositories.map { ($0.fullName.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            )
            return await api.runs(statuses: statuses)
                .map { runs in
                    runs.compactMap { run in
                        run.repo.flatMap { byName[$0.lowercased()] }
                            .map { DepotListedRun(run: run, repository: $0) }
                    }
                }
        }
        return await repositories.traverseAsync(concurrency: query.concurrency) { repository in
            await api.runs(statuses: statuses, repo: repository.fullName)
                .map { runs in runs.map { DepotListedRun(run: $0, repository: repository) } }
        }
        .map { $0.flatMap { $0 } }
    }

    /// Each run's workflows that have one of the query's statuses: a running run can have
    /// finished ones.
    func workflows(
        of runs: [DepotListedRun],
        query: StatusQuery
    ) async -> Result<[DepotActiveWorkflow], RunnersError> {
        let api = api
        return await runs.uniqued(by: \.run.runId)
            .traverseAsync(concurrency: query.concurrency) { listed in
                await api.runStatus(listed.run.runId)
                    .map { status in
                        (status.workflows ?? []).map { workflow in
                            DepotActiveWorkflow(
                                workflow: DepotWorkflowRun(
                                    workflow,
                                    of: listed.run,
                                    orgID: status.orgId
                                ),
                                repository: listed.repository,
                                jobs: workflow.jobs ?? []
                            )
                        }
                    }
            }
            .map { found in
                found.flatMap { $0 }.filter { query.statuses.contains($0.workflow.run.status) }
            }
    }

    /// With jobs, each unfinished job is read on its own; finished ones keep what
    /// `GetRunStatus` says of them.
    func activeRuns(
        _ workflows: [DepotActiveWorkflow],
        query: StatusQuery
    ) async -> Result<[ActiveRun], RunnersError> {
        guard query.includeJobs else {
            return .success(
                workflows.map { ActiveRun(repository: $0.repository, run: $0.workflow.run) }
            )
        }
        let api = api
        let unfinished = workflows.flatMap(\.jobs).filter(\.isUnfinished).map(\.jobId)
        return await unfinished.uniqued(by: \.self)
            .traverseAsync(concurrency: query.concurrency) { await api.job($0) }
            .map { read in
                let byID = Dictionary(
                    read.map { ($0.jobId, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                return workflows.map { active in
                    let url = active.workflow.webURL
                    return ActiveRun(
                        repository: active.repository,
                        run: active.workflow.run,
                        jobs: active.jobs.map {
                            byID[$0.jobId]?.job(webURL: url) ?? $0.job(webURL: url)
                        }
                    )
                }
            }
    }

    /// `GetWorkflow`: how the workflow ended, with its jobs' times.
    public func latest(_ run: ActiveRun, query: StatusQuery) async -> Result<
        ActiveRun, RunnersError
    > {
        await api.workflow(run.run.id)
            .map { workflow in
                let read = workflow.workflowRun
                return ActiveRun(
                    repository: run.repository,
                    run: read.run,
                    jobs: query.includeJobs
                        ? workflow.latestJobs.map { $0.job(webURL: read.webURL) } : nil
                )
            }
    }
}
