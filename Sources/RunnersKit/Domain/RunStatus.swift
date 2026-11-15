/// Where a run or a job is in its life, in terms every service maps onto.
public enum RunStatus: String, Codable, Sendable, CaseIterable {
    /// Ready and waiting for a runner.
    case queued
    /// Held back by something else first: a concurrency group, earlier stages, a resource.
    case pending
    /// Waiting for a person or a timer: an approval, a manual action, a delay.
    case waiting
    case running
    case completed
    /// A status the service reported that this library does not know.
    case unknown

    /// The statuses of runs that have not finished.
    public static let active: [RunStatus] = [.running, .queued, .waiting, .pending]

    /// What a running service phrases as a word: `running 2m`, `queued 5s`.
    public var phrase: String {
        rawValue
    }
}
