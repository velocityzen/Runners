/// How a finished run or job ended.
public enum Conclusion: String, Codable, Sendable, CaseIterable {
    case success
    case failure
    case cancelled
    case skipped
    case neutral
    case timedOut = "timed_out"
    case actionRequired = "action_required"
    /// A conclusion the service reported that this library does not know.
    case unknown

    public var isFailure: Bool {
        self == .failure || self == .timedOut
    }

    /// How it reads in a sentence: `timed out`, `action required`.
    public var phrase: String {
        switch self {
            case .timedOut: "timed out"
            case .actionRequired: "action required"
            default: rawValue
        }
    }

    /// Finished with nothing to look at.
    public var hasPassed: Bool {
        self == .success || self == .skipped || self == .neutral
    }
}
