extension RunStatus {
    /// A GitHub Actions job's status as Depot gives it. `waiting` is GitHub's: a job held for
    /// an environment's approval or wait timer.
    init(depotGitHub raw: String?) {
        self =
            switch raw {
                case DepotGitHubJob.queued: .queued
                case DepotGitHubJob.waiting: .waiting
                case DepotGitHubJob.running: .running
                case DepotGitHubJob.finished: .completed
                default: .unknown
            }
    }

    /// The job status to ask `ListGithubActionsJobs` for.
    var depotGitHubValue: String? {
        switch self {
            case .queued: DepotGitHubJob.queued
            case .waiting: DepotGitHubJob.waiting
            case .running: DepotGitHubJob.running
            case .pending, .completed, .unknown: nil
        }
    }
}

extension Conclusion {
    /// How a finished job ended; nil until it has.
    init?(depotGitHub raw: String?) {
        switch raw {
            case nil, "", "GITHUB_ACTIONS_JOB_CONCLUSION_UNSPECIFIED": return nil
            case "GITHUB_ACTIONS_JOB_CONCLUSION_SUCCESS": self = .success
            case "GITHUB_ACTIONS_JOB_CONCLUSION_FAILURE": self = .failure
            case "GITHUB_ACTIONS_JOB_CONCLUSION_CANCELLED": self = .cancelled
            case "GITHUB_ACTIONS_JOB_CONCLUSION_SKIPPED": self = .skipped
            case "GITHUB_ACTIONS_JOB_CONCLUSION_NEUTRAL": self = .neutral
            default: self = .unknown
        }
    }
}
