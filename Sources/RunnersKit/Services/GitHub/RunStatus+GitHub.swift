extension RunStatus {
    /// A GitHub run or job status.
    init(gitHub raw: String) {
        self =
            switch raw {
                case "queued", "requested": .queued
                case "pending": .pending
                case "waiting": .waiting
                case "in_progress": .running
                case "completed": .completed
                default: .unknown
            }
    }

    /// The GitHub statuses to ask for, one request each, to find runs with this status.
    var gitHubQueryValues: [String] {
        switch self {
            case .running: ["in_progress"]
            case .queued: ["queued"]
            case .pending: ["pending"]
            case .waiting: ["waiting"]
            case .completed, .unknown: []
        }
    }
}

extension Conclusion {
    /// A GitHub run or job conclusion.
    init(gitHub raw: String) {
        self =
            switch raw {
                case "success": .success
                case "failure", "startup_failure": .failure
                case "cancelled": .cancelled
                case "skipped": .skipped
                case "neutral", "stale": .neutral
                case "timed_out": .timedOut
                case "action_required": .actionRequired
                default: .unknown
            }
    }
}
