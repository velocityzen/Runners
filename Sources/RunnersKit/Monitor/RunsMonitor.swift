import FP
import Foundation

/// Takes snapshots of the unfinished runs a CI service knows about.
public struct RunsMonitor: Sendable {
    public let service: any CIService
    let now: @Sendable () -> Date

    public init(service: any CIService, now: @escaping @Sendable () -> Date = { Date() }) {
        self.service = service
        self.now = now
    }

    public func snapshot(_ query: StatusQuery) async -> Result<StatusSnapshot, RunnersError> {
        await service.scope(for: query)
            .flatMapAsync { scope in await snapshot(query, in: scope) }
    }

    /// A snapshot of the runs in a scope read earlier.
    public func snapshot(
        _ query: StatusQuery,
        in scope: MonitorScope
    ) async -> Result<StatusSnapshot, RunnersError> {
        await ResultDo<RunnersError>()
            .bindAsync { await service.activeRuns(in: scope.repositories, query: query) }
            .letAsync { _ in await service.rateLimit() }
            .map { runs, rateLimit in
                StatusSnapshot(
                    provider: service.provider,
                    owner: scope.owner,
                    repositoryCount: scope.repositoryCount,
                    runs: ActiveRun.ordered(runs),
                    rateLimit: rateLimit,
                    fetchedAt: now()
                )
            }
    }
}
