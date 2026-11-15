import FP
import FPPipe

/// A pipeline found through one of its unfinished jobs.
struct GitLabActivePipeline: Sendable, Hashable {
    let repository: Repository
    let id: Int
    let status: RunStatus
    /// The commit title, which the pipeline itself does not carry.
    let title: String?
    let actor: String?

    /// One per pipeline that has not finished, from a project's unfinished jobs.
    static func from(_ jobs: [GitLabJob], in repository: Repository) -> [GitLabActivePipeline] {
        jobs.compactMap { job in
            job.pipeline.map { pipeline in
                GitLabActivePipeline(
                    repository: repository,
                    id: pipeline.id,
                    status: RunStatus(gitLab: pipeline.status),
                    title: job.commit?.title,
                    actor: job.user?.username
                )
            }
        }
        .filter { $0.status != .completed }
        .uniqued(by: \.id)
    }

    func activeRun(_ details: GitLabPipeline, jobs: [GitLabJob]?) -> ActiveRun {
        ActiveRun(
            repository: repository,
            run: details.run(title: title, actor: actor),
            jobs: jobs.map { $0.map(\.job) }
        )
    }
}

extension GitLabService {
    /// One request per project finds its unfinished jobs, and through them its unfinished
    /// pipelines; then each pipeline is read, with its jobs when asked.
    public func activeRuns(
        in repositories: [Repository],
        query: StatusQuery
    ) async -> Result<[ActiveRun], RunnersError> {
        let api = api
        let statuses = query.statuses
        return await Pipe<ActiveRun, RunnersError> {
            From(repositories)
            AsyncFlatMap(concurrency: query.concurrency) { (repository: Repository) in
                await api.activePipelines(in: repository)
            }
            FlatMapSequence { (pipelines: [GitLabActivePipeline]) in pipelines }
            Filter { (pipeline: GitLabActivePipeline) in statuses.contains(pipeline.status) }
            AsyncFlatMap(concurrency: query.concurrency) { (pipeline: GitLabActivePipeline) in
                await api.activeRun(pipeline, includeJobs: query.includeJobs)
            }
        }
        .toResult()
    }
}

extension GitLabAPI {
    func activePipelines(
        in repository: Repository
    ) async -> Result<[GitLabActivePipeline], RunnersError> {
        await unfinishedJobs(in: repository.id)
            .map { GitLabActivePipeline.from($0, in: repository) }
    }

    func activeRun(
        _ pipeline: GitLabActivePipeline,
        includeJobs: Bool
    ) async -> Result<ActiveRun, RunnersError> {
        guard includeJobs else {
            return await self.pipeline(pipeline.id, in: pipeline.repository.id)
                .map { pipeline.activeRun($0, jobs: nil) }
        }
        let api = self
        return await withAll(
            await api.pipeline(pipeline.id, in: pipeline.repository.id),
            await api.jobs(ofPipeline: pipeline.id, in: pipeline.repository.id)
        )
        .map { details, jobs in pipeline.activeRun(details, jobs: jobs) }
    }
}
