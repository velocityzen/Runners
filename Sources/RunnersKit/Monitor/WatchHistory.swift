import FP

/// What a watch remembers between snapshots, so a run that finishes stays on show with how it
/// ended until a newer run of the same workflow on the same branch takes its place.
struct WatchHistory: Sendable {
    /// Runs last seen unfinished, by id, including ones whose final state could not be read yet.
    private(set) var unfinished: [String: ActiveRun] = [:]
    /// Finished runs still on show.
    private(set) var finished: [ActiveRun] = []

    /// Runs that were unfinished and are not among the snapshot's: they ended, or left the
    /// statuses asked for.
    func ended(in snapshot: StatusSnapshot) -> [ActiveRun] {
        let current = Set(snapshot.runs.map(\.id))
        return unfinished.values
            .filter { !current.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    /// Takes in a snapshot and what became of the runs that ended, and gives the snapshot with
    /// the finished runs still on show.
    ///
    /// A run read as finished goes on show. A run that is gone or not finished yet leaves, and
    /// a run that could not be read is tried again next time.
    mutating func record(
        _ snapshot: StatusSnapshot,
        ended: [(run: ActiveRun, latest: Result<ActiveRun, RunnersError>)]
    ) -> StatusSnapshot {
        let retries = ended.compactMap { $0.latest.isRetryable ? $0.run : nil }
        let justFinished = ended.map(\.latest).successes().filter(\.isFinished)
        unfinished = Dictionary(
            (snapshot.runs + retries).map { ($0.id, $0) },
            uniquingKeysWith: { new, _ in new }
        )
        finished = Self.onShow(finished + justFinished, besides: snapshot.runs)
        return snapshot.with(runs: ActiveRun.ordered(snapshot.runs + finished))
    }

    /// Finished runs that are not running again and that no newer run of theirs replaced.
    static func onShow(_ finished: [ActiveRun], besides current: [ActiveRun]) -> [ActiveRun] {
        let running = Set(current.map(\.id))
        let everything = current + finished
        return finished.uniqued(by: \.id)
            .filter { !running.contains($0.id) }
            .filter { run in !everything.contains { $0.replaces(run) } }
    }
}

extension ActiveRun {
    public var isFinished: Bool {
        run.status == .completed
    }

    /// A newer run of the same workflow on the same branch of the same repository.
    func replaces(_ other: ActiveRun) -> Bool {
        id != other.id
            && repository.id == other.repository.id
            && run.name == other.run.name
            && run.branch == other.run.branch
            && run.createdAt > other.run.createdAt
    }
}

extension Result where Failure == RunnersError {
    /// A failure worth asking again about; a run that is gone is not.
    var isRetryable: Bool {
        guard case .failure(let error) = self else { return false }
        if case .notFound = error { return false }
        return true
    }
}
