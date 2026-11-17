extension RunStatus {
    /// The phases before a runner is up: the build waits for compute, then gets it ready.
    static let codeBuildWaitingPhases: Set<String> = ["SUBMITTED", "QUEUED", "PROVISIONING"]

    /// An unfinished build in this phase: queued until a runner is up, then running.
    init(codeBuildPhase phase: String?) {
        self =
            phase.map { Self.codeBuildWaitingPhases.contains($0) ? .queued : .running } ?? .queued
    }

    /// A phase in words: `download source` for `DOWNLOAD_SOURCE`.
    static func codeBuildPhrase(_ phase: String) -> String {
        phase.lowercased().replacing("_", with: " ")
    }
}

extension Conclusion {
    /// How a finished build ended.
    init(codeBuild status: String?) {
        self =
            switch status {
                case "SUCCEEDED": .success
                case "FAILED", "FAULT": .failure
                case "TIMED_OUT": .timedOut
                case "STOPPED": .cancelled
                default: .unknown
            }
    }
}
