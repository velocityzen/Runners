import FP
import FPPipe

/// One request: the pipelines of one repository with one Woodpecker status.
struct WoodpeckerListing: Sendable {
    let repository: Repository
    let status: String
}

extension WoodpeckerService {
    /// One request per repository and status, then, with jobs, one per pipeline: only reading
    /// a pipeline on its own gives its workflows.
    public func activeRuns(
        in repositories: [Repository],
        query: StatusQuery
    ) async -> Result<[ActiveRun], RunnersError> {
        let api = api
        let statuses = query.statuses.compactMap(\.woodpeckerQueryValue)
        return await Pipe<ActiveRun, RunnersError> {
            From(repositories)
            FlatMapSequence { (repository: Repository) in
                statuses.map { WoodpeckerListing(repository: repository, status: $0) }
            }
            AsyncFlatMap(concurrency: query.concurrency) { (listing: WoodpeckerListing) in
                await api.pipelines(of: listing.repository.id, status: listing.status)
                    .map { pipelines in
                        pipelines.map { api.activeRun($0, in: listing.repository, jobs: false) }
                    }
            }
            FlatMapSequence { (runs: [ActiveRun]) in runs }
            if query.includeJobs {
                AsyncFlatMap(concurrency: query.concurrency) { (run: ActiveRun) in
                    await api.read(run.run.id, in: run.repository, jobs: true)
                }
            }
        }
        .toResult()
        .map { runs in runs.uniqued(by: \.id).filter { query.statuses.contains($0.run.status) } }
    }

    public func latest(_ run: ActiveRun, query: StatusQuery) async -> Result<
        ActiveRun, RunnersError
    > {
        await api.read(run.run.id, in: run.repository, jobs: query.includeJobs)
    }
}

extension WoodpeckerAPI {
    /// A pipeline read on its own, which brings its workflows.
    func read(
        _ number: String,
        in repository: Repository,
        jobs: Bool
    ) async -> Result<ActiveRun, RunnersError> {
        await pipeline(number, of: repository.id)
            .map { activeRun($0, in: repository, jobs: jobs) }
    }

    /// `https://ci.codeberg.org/repos/11239/pipeline/1097`
    func activeRun(
        _ pipeline: WoodpeckerPipeline,
        in repository: Repository,
        jobs: Bool
    ) -> ActiveRun {
        let url = server.appending(path: "repos/\(repository.id)/pipeline/\(pipeline.number)")
        let run = pipeline.run(webURL: url)
        return ActiveRun(
            repository: repository,
            run: run,
            jobs: jobs
                ? (pipeline.workflows ?? []).map { $0.job(createdAt: run.createdAt, webURL: url) }
                : nil
        )
    }
}
