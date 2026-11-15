import FP
import Foundation

/// Finds the GitHub Actions runs of a user, an organization or a set of repositories that have
/// not finished yet.
public struct ActionsMonitor: Sendable {
    public let client: GitHubClient
    let now: @Sendable () -> Date

    public init(client: GitHubClient, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    public func snapshot(_ query: StatusQuery) async -> Result<StatusSnapshot, GitHubError> {
        await ResultDo<GitHubError>()
            .bindAsync { await scope(for: query) }
            .bindAsync { scope in await activeRuns(in: scope.repositories, query: query) }
            .letAsync { _, _ in await rateLimitIfReported() }
            .map { scope, runs, rateLimit in
                StatusSnapshot(
                    owner: scope.owner,
                    repositoryCount: scope.repositories.count,
                    runs: runs,
                    rateLimit: rateLimit,
                    fetchedAt: now()
                )
            }
    }

    /// The quota is extra information: a server without one is no reason to fail.
    func rateLimitIfReported() async -> RateLimit? {
        await client.rateLimit()
            .map(Optional.some)
            .getOrElse(nil)
    }
}
