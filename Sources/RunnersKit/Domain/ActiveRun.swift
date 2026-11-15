/// A run with its repository and, when asked for, its jobs. Unfinished, except for the finished
/// runs a watch keeps on show.
public struct ActiveRun: Codable, Sendable, Hashable, Identifiable {
    public let repository: Repository
    public let run: Run
    public let jobs: [Job]?

    public init(repository: Repository, run: Run, jobs: [Job]? = nil) {
        self.repository = repository
        self.run = run
        self.jobs = jobs
    }

    /// Unique across repositories and services.
    public var id: String {
        "\(repository.id)/\(run.id)"
    }

    public func with(jobs: [Job]) -> ActiveRun {
        ActiveRun(repository: repository, run: run, jobs: jobs)
    }
}
