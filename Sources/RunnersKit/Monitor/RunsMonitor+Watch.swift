import FP

extension RunsMonitor {
    /// A snapshot each time the sequence is read, at most once per `interval`.
    ///
    /// The first comes at once. Nothing is fetched until it is asked for, and a failure is an
    /// element rather than the end: the next read tries again. The sequence finishes when the
    /// reading task is cancelled.
    public func watch(
        _ query: StatusQuery,
        every interval: Duration
    ) -> some AsyncSequence<Result<StatusSnapshot, RunnersError>, Never> {
        withRepeat(interval: interval) {
            await snapshot(query)
        }
    }
}
