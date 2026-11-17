import FP
import Foundation

extension RunsMonitor {
    /// A snapshot of the runners of the query's target.
    public func runners(_ query: StatusQuery) async -> Result<RunnersSnapshot, RunnersError> {
        await ResultDo<RunnersError>()
            .bindAsync { await service.runners(for: query) }
            .letAsync { _ in await service.rateLimit() }
            .map { listing, rateLimit in
                RunnersSnapshot(
                    provider: service.provider,
                    listing: listing,
                    rateLimit: rateLimit,
                    fetchedAt: now()
                )
            }
    }

    /// A runners snapshot each time the sequence is read, the first at once, then with at
    /// least `interval` between the end of one and the start of the next. A failure is an
    /// element rather than the end. The sequence finishes when the reading task is cancelled.
    public func watchRunners(
        _ query: StatusQuery,
        every interval: Duration
    ) -> some AsyncSequence<Result<RunnersSnapshot, RunnersError>, Never> {
        withRepeat(interval: interval, from: .finish) { await runners(query) }
    }
}
