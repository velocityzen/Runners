/// A run that has not finished, with its repository and, when asked for, its jobs.
public struct ActiveRun: Codable, Sendable, Hashable, Identifiable {
    public let repository: Repository
    public let run: WorkflowRun
    public let jobs: [WorkflowJob]?

    public init(repository: Repository, run: WorkflowRun, jobs: [WorkflowJob]? = nil) {
        self.repository = repository
        self.run = run
        self.jobs = jobs
    }

    public var id: Int { run.id }

    func with(jobs: [WorkflowJob]) -> ActiveRun {
        ActiveRun(repository: repository, run: run, jobs: jobs)
    }
}
