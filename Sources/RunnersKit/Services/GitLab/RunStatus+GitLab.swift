extension RunStatus {
    /// A GitLab pipeline or job status.
    init(gitLab raw: String) {
        self =
            switch raw {
                case "created", "waiting_for_resource", "preparing": .pending
                case "pending": .queued
                case "running", "canceling": .running
                case "manual", "scheduled": .waiting
                case "success", "failed", "canceled", "skipped": .completed
                default: .unknown
            }
    }

    /// The job statuses that mean a pipeline is still going, for `scope[]`.
    static let gitLabUnfinishedJobScopes = [
        "created", "waiting_for_resource", "preparing", "pending", "running", "scheduled",
    ]
}

extension Conclusion {
    /// GitLab has no separate conclusion: a finished status is one. `nil` while unfinished.
    init?(gitLab raw: String) {
        switch raw {
            case "success": self = .success
            case "failed": self = .failure
            case "canceled": self = .cancelled
            case "skipped": self = .skipped
            default: return nil
        }
    }
}
