import FP
import Foundation
import Synchronization

extension RunsMonitor {
    /// A snapshot each time the sequence is read, at most once per `interval`.
    ///
    /// The first comes at once. Nothing is fetched until it is asked for, and a failure is an
    /// element rather than the end: the next read tries again. The repositories to check are
    /// read again only once `rescan` has passed, or after a failure. A run that finishes is
    /// read once more and stays in the snapshots with how it ended, until a newer run of the
    /// same workflow on the same branch replaces it. The sequence finishes when the reading
    /// task is cancelled.
    ///
    /// The sequence keeps one scope and one history, so read it in one loop: a second loop
    /// over the same sequence would share them. For another loop, call `watch` again.
    public func watch(
        _ query: StatusQuery,
        every interval: Duration,
        rescan: Duration = .seconds(300)
    ) -> some AsyncSequence<Result<StatusSnapshot, RunnersError>, Never> {
        let state = WatchState(monitor: self, query: query, rescan: rescan)
        return withRepeat(interval: interval) { await state.next() }
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

/// What a watch keeps between snapshots: the scope, reused for a while, and the runs it saw
/// finish, through a ``WatchHistory``.
///
/// `withRepeat` never starts a call before the last one returns, so nothing changes the state
/// between a read and the write after it. The lock is there only because the call is
/// `@Sendable`; it is never held across an `await`.
final class WatchState: Sendable {
    struct Kept {
        var scope: ReadScope?
        var history = WatchHistory()
    }

    let monitor: RunsMonitor
    let query: StatusQuery
    let rescan: Duration
    private let kept = Mutex(Kept())

    init(monitor: RunsMonitor, query: StatusQuery, rescan: Duration) {
        self.monitor = monitor
        self.query = query
        self.rescan = rescan
    }

    /// A snapshot, with the runs that finished since the last one still on show.
    func next() async -> Result<StatusSnapshot, RunnersError> {
        await snapshot().mapAsync { snapshot in
            let ended = kept.withLock { $0.history.ended(in: snapshot) }
            let latest = await monitor.latest(of: ended, query: query)
            return kept.withLock { $0.history.record(snapshot, ended: latest) }
        }
    }

    /// A snapshot in the kept scope, or in a fresh one. A failure drops the scope, in case a
    /// repository in it is gone.
    func snapshot() async -> Result<StatusSnapshot, RunnersError> {
        let scope = await currentScope(at: monitor.now())
        let snapshot = await scope.flatMapAsync { read in
            await monitor.snapshot(query, in: read.scope)
        }
        kept.withLock { $0.scope = snapshot.isSuccess ? try? scope.get() : nil }
        return snapshot
    }

    func currentScope(at now: Date) async -> Result<ReadScope, RunnersError> {
        if let scope = kept.withLock({ $0.scope }), scope.isFresh(at: now, within: rescan) {
            return .success(scope)
        }
        return await monitor.service.scope(for: query)
            .map { ReadScope(scope: $0, readAt: now) }
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
