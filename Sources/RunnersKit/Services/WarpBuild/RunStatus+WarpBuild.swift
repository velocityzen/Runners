extension RunStatus {
    /// A runner instance's status, read as its job's. WarpBuild doesn't document what each
    /// means; this follows the lifecycle its names describe. An instance being allocated has
    /// a job waiting for it, so it is queued; a running one runs the job. One that has gone
    /// back to a warm pool (`polling`, `suspending`, `suspended`) or away (`completed`,
    /// `purging`, `purged`) is done with it.
    init(warpBuild raw: String?) {
        self =
            switch raw {
                case "allocating", "allocated": .queued
                case "running": .running
                case "init_triggered", "init_complete", "polling", "suspending", "suspended",
                    "completed", "purging", "purged":
                    .completed
                default: .unknown
            }
    }

    /// The instance statuses to ask `GET /runner_instance` for.
    var warpBuildValues: [String] {
        switch self {
            case .queued: ["allocating", "allocated"]
            case .running: ["running"]
            case .pending, .waiting, .completed, .unknown: []
        }
    }
}
