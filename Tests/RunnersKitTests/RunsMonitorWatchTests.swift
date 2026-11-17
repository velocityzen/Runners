import FP
import Foundation
import Synchronization
import Testing

@testable import RunnersKit

@Suite("Watching")
struct RunsMonitorWatchTests {
    /// A service that counts its scope lookups and run listings, and fails the ones `failing`
    /// and `failingRuns` name (1-based). Each run listing takes `listingTakes`.
    final class CountingService: CIService {
        let provider: any Provider = GitHubProvider()
        let failing: Set<Int>
        let failingRuns: Set<Int>
        let listingTakes: Duration
        private let lookups = Atomic(0)
        private let listings = Atomic(0)
        private let spans = Mutex<[Range<ContinuousClock.Instant>]>([])

        init(failing: Set<Int> = [], failingRuns: Set<Int> = [], listingTakes: Duration = .zero) {
            self.failing = failing
            self.failingRuns = failingRuns
            self.listingTakes = listingTakes
        }

        /// When each run listing started and ended, in order.
        var listingSpans: [Range<ContinuousClock.Instant>] {
            spans.withLock { $0 }
        }

        var count: Int {
            lookups.load(ordering: .relaxed)
        }

        var runListings: Int {
            listings.load(ordering: .relaxed)
        }

        func scope(for query: StatusQuery) async -> Result<MonitorScope, RunnersError> {
            let lookup = lookups.add(1, ordering: .relaxed).newValue
            return failing.contains(lookup)
                ? .failure(.server(status: 502, message: "Bad Gateway"))
                : .success(
                    MonitorScope(owner: nil, repositories: [Fixtures.repository("octo/app")])
                )
        }

        func activeRuns(
            in repositories: [Repository],
            query: StatusQuery
        ) async -> Result<[ActiveRun], RunnersError> {
            let start = ContinuousClock.now
            let listing = listings.add(1, ordering: .relaxed).newValue
            if listingTakes > .zero {
                try? await Task.sleep(for: listingTakes)
            }
            spans.withLock { $0.append(start..<ContinuousClock.now) }
            return failingRuns.contains(listing) ? .failure(.notFound("octo/app")) : .success([])
        }

        func latest(_ run: ActiveRun, query: StatusQuery) async -> Result<ActiveRun, RunnersError> {
            .success(run)
        }

        func rateLimit() async -> RateLimit? {
            nil
        }
    }

    let query = StatusQuery(target: .authenticatedUser)

    @Test("gives a snapshot at once, then one per read")
    func ticks() async {
        let service = CountingService()
        let monitor = RunsMonitor(service: service, now: { Fixtures.now })
        var results: [Result<StatusSnapshot, RunnersError>] = []
        for await result in monitor.watch(query, every: .milliseconds(1)).prefix(3) {
            results.append(result)
        }
        #expect(results.count == 3)
        #expect(results.filter(\.isSuccess).count == 3)
        #expect(service.runListings == 3)
        #expect(service.count == 1)
    }

    @Test("waits the whole interval after a snapshot, however long it took")
    func slowSnapshot() async throws {
        let service = CountingService(listingTakes: .milliseconds(50))
        let monitor = RunsMonitor(service: service)
        for await _ in monitor.watch(query, every: .milliseconds(50)).prefix(2) {}
        let spans = service.listingSpans
        try #require(spans.count == 2)
        // Counted from the start, the second would begin as the first ended.
        #expect(spans[0].upperBound.duration(to: spans[1].lowerBound) >= .milliseconds(50))
    }

    @Test("reads the repositories again once the rescan time has passed")
    func rescan() async {
        let service = CountingService()
        let minute = Received()
        let monitor = RunsMonitor(service: service) {
            Fixtures.now.addingTimeInterval(Double(minute.count.load(ordering: .relaxed)) * 60)
        }
        var snapshots = monitor.watch(query, every: .milliseconds(1), rescan: .seconds(150))
            .makeAsyncIterator()
        for now in 0..<5 {
            minute.count.store(now, ordering: .relaxed)
            _ = await snapshots.next(isolation: #isolation)
        }
        // Minutes 0, 1 and 2 share the scope read at 0; 3 and 4 the one read at 3.
        #expect(service.count == 2)
        #expect(service.runListings == 5)
    }

    @Test("reads the repositories again after any failure")
    func rescanAfterFailure() async {
        let service = CountingService(failingRuns: [2])
        let monitor = RunsMonitor(service: service, now: { Fixtures.now })
        var results: [Result<StatusSnapshot, RunnersError>] = []
        for await result in monitor.watch(query, every: .milliseconds(1)).prefix(4) {
            results.append(result)
        }
        #expect(results.map(\.isSuccess) == [true, false, true, true])
        #expect(service.count == 2)
    }

    @Test("keeps going after a failure")
    func failure() async {
        let service = CountingService(failing: [1])
        let monitor = RunsMonitor(service: service)
        var results: [Result<StatusSnapshot, RunnersError>] = []
        for await result in monitor.watch(query, every: .milliseconds(1)).prefix(2) {
            results.append(result)
        }
        #expect(results.map(\.isSuccess) == [false, true])
        #expect(service.count == 2)
    }

    @Test("fetches only when read")
    func pull() async throws {
        let service = CountingService()
        var snapshots = RunsMonitor(service: service).watch(query, every: .milliseconds(1))
            .makeAsyncIterator()
        _ = await snapshots.next(isolation: #isolation)
        try await Task.sleep(for: .milliseconds(50))
        #expect(service.count == 1)
    }

    @Test("finishes when the reading task is cancelled")
    func cancellation() async {
        let service = CountingService()
        let monitor = RunsMonitor(service: service)
        let received = Received()
        let reader = Task<Void, Never> {
            for await _ in monitor.watch(query, every: .seconds(3600)) {
                received.count.add(1, ordering: .relaxed)
            }
        }
        // Cancelled while waiting out the hour after the first snapshot.
        while received.count.load(ordering: .relaxed) == 0 {
            await Task.yield()
        }
        reader.cancel()
        await reader.value
        #expect(received.count.load(ordering: .relaxed) == 1)
        #expect(service.count == 1)
    }

    final class Received: Sendable {
        let count = Atomic(0)
    }
}
