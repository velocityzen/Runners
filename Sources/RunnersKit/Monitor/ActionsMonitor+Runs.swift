import FP
import FPPipe

/// One request: the runs of one repository with one status.
struct RunListing: Sendable {
    let repository: Repository
    let status: ActionStatus

    static func all(_ repository: Repository, statuses: [ActionStatus]) -> [RunListing] {
        statuses.map { RunListing(repository: repository, status: $0) }
    }
}

extension ActionsMonitor {
    /// Skips repositories without workflows, then fans out over every repository × status, then
    /// over every run for its jobs.
    func activeRuns(in repositories: [Repository], query: StatusQuery) async -> Result<[ActiveRun], GitHubError> {
        let client = client
        return await Pipe<ActiveRun, GitHubError> {
            From(repositories)
            AsyncFlatMap(concurrency: query.concurrency) { (repository: Repository) in
                await client.ifHasWorkflows(repository)
            }
            CompactMap { (repository: Repository?) in repository }
            FlatMapSequence { (repository: Repository) in
                RunListing.all(repository, statuses: query.statuses)
            }
            AsyncFlatMap(concurrency: query.concurrency) { (listing: RunListing) in
                await client.activeRuns(listing)
            }
            FlatMapSequence { (runs: [ActiveRun]) in runs }
            if query.includeJobs {
                AsyncFlatMap(concurrency: query.concurrency) { (run: ActiveRun) in
                    await client.withJobs(run)
                }
            }
        }
        .toResult()
        .map(ActiveRun.ordered)
    }
}

extension GitHubClient {
    /// The repository when it has workflows, `nil` when nothing there can run.
    func ifHasWorkflows(_ repository: Repository) async -> Result<Repository?, GitHubError> {
        await workflowCount(in: repository)
            .map { $0 > 0 ? repository : nil }
    }

    func activeRuns(_ listing: RunListing) async -> Result<[ActiveRun], GitHubError> {
        await workflowRuns(in: listing.repository, status: listing.status)
            .map { runs in runs.map { ActiveRun(repository: listing.repository, run: $0) } }
    }

    func withJobs(_ run: ActiveRun) async -> Result<ActiveRun, GitHubError> {
        await jobs(of: run.run, in: run.repository)
            .map(run.with(jobs:))
    }
}
