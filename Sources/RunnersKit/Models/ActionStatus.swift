/// The status of a workflow run or job.
public enum ActionStatus: String, Codable, Sendable, CaseIterable {
    case requested
    case queued
    case pending
    case waiting
    case inProgress = "in_progress"
    case completed
    /// A status this library does not know yet.
    case unknown

    /// What a status query looks for by default: one API request per status per repository.
    public static let active: [ActionStatus] = [.inProgress, .queued, .waiting, .pending]

    /// Statuses that mean a run has not finished, and so can be queried for.
    public static let queryable: [ActionStatus] = [.inProgress, .queued, .waiting, .pending, .requested]

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ActionStatus(rawValue: raw) ?? .unknown
    }
}
