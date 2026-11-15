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
        await ResultDo<RunnersError>()
            .bindAsync { await service.scope(for: query) }
            .bindAsync { scope in await service.activeRuns(in: scope.repositories, query: query) }
            .letAsync { _, _ in await service.rateLimit() }
            .map { scope, runs, rateLimit in
                StatusSnapshot(
                    provider: service.provider,
                    owner: scope.owner,
                    repositoryCount: scope.repositories.count,
                    runs: ActiveRun.ordered(runs),
                    rateLimit: rateLimit,
                    fetchedAt: now()
                )
            }
    }
}
