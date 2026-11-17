extension RunStatus {
    /// A run's status. `blocked` waits on something before it can start; a run from a fork or
    /// an untrusted user that awaits approval waits for a person, whether Forgejo calls it
    /// `blocked` or, as older versions did, `waiting`.
    init(forgejoRun raw: String, awaitsApproval: Bool) {
        if awaitsApproval, raw == "waiting" || raw == "blocked" {
            self = .waiting
        } else {
            self.init(forgejoJob: raw)
        }
    }

    /// A job's status: `waiting` for a runner, `blocked` by the jobs it needs.
    init(forgejoJob raw: String) {
        self =
            switch raw {
                case "waiting": .queued
                case "blocked": .pending
                case "running": .running
                case "success", "failure", "cancelled", "skipped": .completed
                default: .unknown
            }
    }

    /// The Forgejo statuses to ask for to find runs with this status. One request takes
    /// them all.
    var forgejoQueryValues: [String] {
        switch self {
            case .running: ["running"]
            case .queued: ["waiting"]
            case .pending: ["blocked"]
            case .waiting: ["blocked", "waiting"]
            case .completed, .unknown: []
        }
    }
}

extension Conclusion {
    /// How a Forgejo run or job ended.
    init(forgejo raw: String) {
        self =
            switch raw {
                case "success": .success
                case "failure": .failure
                case "cancelled": .cancelled
                case "skipped": .skipped
                default: .unknown
            }
    }
}
