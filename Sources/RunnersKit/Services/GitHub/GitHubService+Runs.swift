import FP
import FPPipe

/// One request: the runs of one repository with one GitHub status.
struct GitHubRunListing: Sendable {
    let repository: Repository
    let status: String

    static func all(_ repository: Repository, statuses: [String]) -> [GitHubRunListing] {
        statuses.map { GitHubRunListing(repository: repository, status: $0) }
    }
}

extension GitHubService {
    /// Skips repositories without workflows, then fans out over every repository × status, then
    /// over every run for its jobs.
    public func activeRuns(
        in repositories: [Repository],
        query: StatusQuery
    ) async -> Result<[ActiveRun], RunnersError> {
        let api = api
        let statuses = query.statuses.flatMap(\.gitHubQueryValues)
        return await Pipe<ActiveRun, RunnersError> {
            From(repositories)
            AsyncFlatMap(concurrency: query.concurrency) { (repository: Repository) in
                await api.ifHasWorkflows(repository)
            }
            CompactMap { (repository: Repository?) in repository }
            FlatMapSequence { (repository: Repository) in
                GitHubRunListing.all(repository, statuses: statuses)
            }
            AsyncFlatMap(concurrency: query.concurrency) { (listing: GitHubRunListing) in
                await api.activeRuns(listing)
            }
            FlatMapSequence { (runs: [ActiveRun]) in runs }
            if query.includeJobs {
                AsyncFlatMap(concurrency: query.concurrency) { (run: ActiveRun) in
                    await api.withJobs(run)
                }
            }
        }
        .toResult()
    }
}

extension GitHubAPI {
    /// The repository when it has workflows, `nil` when nothing there can run.
    func ifHasWorkflows(_ repository: Repository) async -> Result<Repository?, RunnersError> {
        await workflowCount(in: repository.fullName)
            .map { $0 > 0 ? repository : nil }
    }

    func activeRuns(_ listing: GitHubRunListing) async -> Result<[ActiveRun], RunnersError> {
        await workflowRuns(in: listing.repository.fullName, status: listing.status)
            .map { runs in runs.map { ActiveRun(repository: listing.repository, run: $0.run) } }
    }

    func withJobs(_ active: ActiveRun) async -> Result<ActiveRun, RunnersError> {
        await jobs(in: active.repository.fullName, runID: active.run.id)
            .map { active.with(jobs: $0.map(\.job)) }
    }
}
