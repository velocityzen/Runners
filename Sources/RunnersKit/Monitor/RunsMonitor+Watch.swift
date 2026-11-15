import Synchronization

extension RunsMonitor {
    /// A snapshot now, then a fresh one each time the stream is read again, `interval` after
    /// that read. Nothing is fetched until it is asked for, and a failure is an element rather
    /// than the end: the next read tries again. The stream finishes when the reading task is
    /// cancelled.
    public func watch(
        _ query: StatusQuery,
        every interval: Duration
    ) -> AsyncStream<Result<StatusSnapshot, RunnersError>> {
        let pace = Pace(interval: interval)

        return AsyncStream {
            guard await pace.wait() else { return nil }
            let result = await snapshot(query)
            return Task.isCancelled ? nil : result
        }
    }
}

/// Lets the first call through at once, and makes each later one wait out the interval.
final class Pace: Sendable {
    let interval: Duration
    private let started = Atomic(false)

    init(interval: Duration) {
        self.interval = interval
    }

    /// False when the waiting task is cancelled.
    func wait() async -> Bool {
        if started.exchange(true, ordering: .relaxed) {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return false
            }
        }
        return !Task.isCancelled
    }
}
