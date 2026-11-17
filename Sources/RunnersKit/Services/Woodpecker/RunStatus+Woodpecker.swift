extension RunStatus {
    /// A pipeline's, workflow's or step's status. `pending` waits for an agent, `blocked`
    /// for someone to approve it, and `created` hasn't been queued yet.
    init(woodpecker raw: String) {
        self =
            switch raw {
                case "pending": .queued
                case "running": .running
                case "blocked": .waiting
                case "created": .pending
                case "success", "failure", "error", "killed", "canceled", "declined", "skipped":
                    .completed
                default: .unknown
            }
    }

    /// The Woodpecker status to ask for to find pipelines with this status, one request
    /// each.
    var woodpeckerQueryValue: String? {
        switch self {
            case .running: "running"
            case .queued: "pending"
            case .waiting: "blocked"
            case .pending: "created"
            case .completed, .unknown: nil
        }
    }
}

extension Conclusion {
    /// How a Woodpecker pipeline or workflow ended. `declined` is an approval refused.
    init(woodpecker raw: String) {
        self =
            switch raw {
                case "success": .success
                case "failure", "error": .failure
                case "killed", "canceled", "declined": .cancelled
                case "skipped": .skipped
                default: .unknown
            }
    }
}
