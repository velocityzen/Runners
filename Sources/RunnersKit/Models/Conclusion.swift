/// How a finished run, job or step ended.
public enum Conclusion: String, Codable, Sendable, CaseIterable {
    case success
    case failure
    case cancelled
    case skipped
    case neutral
    case timedOut = "timed_out"
    case actionRequired = "action_required"
    case stale
    case startupFailure = "startup_failure"
    /// A conclusion this library does not know yet.
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Conclusion(rawValue: raw) ?? .unknown
    }

    public var isFailure: Bool {
        [.failure, .timedOut, .startupFailure].contains(self)
    }
}
