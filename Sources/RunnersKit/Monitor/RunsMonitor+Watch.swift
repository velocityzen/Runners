import FP
import Foundation

extension RunsMonitor {
    /// A snapshot each time the sequence is read, at most once per `interval`.
    ///
    /// The first comes at once. Nothing is fetched until it is asked for, and a failure is an
    /// element rather than the end: the next read tries again. The repositories to check are
    /// read again only once `rescan` has passed, or after a failure. A run that finishes is
    /// read once more and stays in the snapshots with how it ended, until a newer run of the
    /// same workflow on the same branch replaces it. The sequence finishes when the reading
    /// task is cancelled.
    public func watch(
        _ query: StatusQuery,
        every interval: Duration,
        rescan: Duration = .seconds(300)
    ) -> some AsyncSequence<Result<StatusSnapshot, RunnersError>, Never> {
        RunsWatch(
            ticks: withRepeat(interval: interval) {},
            monitor: self,
            query: query,
            rescan: rescan
        )
    }

    /// What became of each run, read at the same time.
    func latest(
        of runs: [ActiveRun],
        query: StatusQuery
    ) async -> [(run: ActiveRun, latest: Result<ActiveRun, RunnersError>)] {
        let service = service
        return await runs.traverseAsync(concurrency: query.concurrency) { run in
            (run: run, latest: await service.latest(run, query: query))
        }
        .get()
    }
}

/// A snapshot per tick that reuses the scope for a while and keeps the runs it saw finish,
/// through a ``WatchHistory``.
struct RunsWatch<Ticks: AsyncSequence<Void, Never>>: AsyncSequence {
    typealias Element = Result<StatusSnapshot, RunnersError>
    typealias Failure = Never

    let ticks: Ticks
    let monitor: RunsMonitor
    let query: StatusQuery
    let rescan: Duration

    func makeAsyncIterator() -> Iterator {
        Iterator(ticks: ticks.makeAsyncIterator(), monitor: monitor, query: query, rescan: rescan)
    }

    struct Iterator: AsyncIteratorProtocol {
        var ticks: Ticks.AsyncIterator
        let monitor: RunsMonitor
        let query: StatusQuery
        let rescan: Duration
        var scope: ReadScope?
        var history = WatchHistory()

        mutating func next() async -> Element? {
            await next(isolation: nil)
        }

        mutating func next(isolation actor: isolated (any Actor)?) async -> Element? {
            guard await ticks.next(isolation: actor) != nil else { return nil }
            let result = await snapshot()
            guard case .success(let snapshot) = result else { return result }
            let ended = await monitor.latest(of: history.ended(in: snapshot), query: query)
            return .success(history.record(snapshot, ended: ended))
        }

        /// A snapshot in the kept scope, or in a fresh one. A failure drops the scope, in case
        /// a repository in it is gone.
        mutating func snapshot() async -> Result<StatusSnapshot, RunnersError> {
            let scope = await currentScope(at: monitor.now())
            let snapshot = await scope.flatMapAsync { [monitor, query] read in
                await monitor.snapshot(query, in: read.scope)
            }
            self.scope = snapshot.isSuccess ? try? scope.get() : nil
            return snapshot
        }

        func currentScope(at now: Date) async -> Result<ReadScope, RunnersError> {
            if let scope, scope.isFresh(at: now, within: rescan) { return .success(scope) }
            return await monitor.service.scope(for: query)
                .map { ReadScope(scope: $0, readAt: now) }
        }
    }
}

/// A scope and when it was read.
struct ReadScope: Sendable {
    let scope: MonitorScope
    let readAt: Date

    func isFresh(at now: Date, within age: Duration) -> Bool {
        now.timeIntervalSince(readAt) < age.seconds
    }
}

extension Duration {
    var seconds: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
