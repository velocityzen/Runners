extension RunStatus {
    /// A Depot CI run's or workflow's status: `queued`, `running`, then `finished`, `failed`
    /// or `cancelled`.
    init(depotRun raw: String?) {
        self =
            switch raw {
                case "queued": .queued
                case "running": .running
                case "finished", "failed", "cancelled": .completed
                default: .unknown
            }
    }

    /// A job's status, which adds `waiting`, a job held by a concurrency group, and
    /// `skipped`.
    init(depotJob raw: String?) {
        switch raw {
            case "waiting": self = .pending
            case "skipped": self = .completed
            default: self.init(depotRun: raw)
        }
    }

    /// The run status to ask `ListRuns` for. A Depot run is never waiting or pending; its
    /// jobs can be.
    var depotQueryValue: String? {
        switch self {
            case .running: "running"
            case .queued: "queued"
            case .waiting, .pending, .completed, .unknown: nil
        }
    }
}

extension Conclusion {
    /// How a finished run, workflow or job ended, as its status says: `finished` is a
    /// success. Nil while it hasn't.
    init?(depotStatus raw: String?) {
        switch raw {
            case "finished": self = .success
            case "failed": self = .failure
            case "cancelled": self = .cancelled
            case "skipped": self = .skipped
            default: return nil
        }
    }

    /// A job's own conclusion, from `GetJob`. Nil while it has none.
    init?(depot raw: String?) {
        switch raw {
            case nil, "": return nil
            case "success": self = .success
            case "failure": self = .failure
            case "cancelled": self = .cancelled
            case "skipped": self = .skipped
            case "timed_out": self = .timedOut
            default: self = .unknown
        }
    }
}
