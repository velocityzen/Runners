extension StatusSnapshot {
    /// Whose runs these are: `octo on GitHub`, or just `GitHub` for a list of repositories.
    public var scope: String {
        owner.map { "\($0.login) on \(provider.name)" } ?? provider.name
    }

    /// `2 active runs in 1 of 12 repositories`, or `no active runs in 12 repositories`, then
    /// ` · 3 finished` when a watch keeps finished runs on show.
    public var summary: String {
        let term = provider.repositoryTerm
        let repositories = counted(repositoryCount, term.singular, term.plural)
        let active = activeRuns
        let activity =
            active.isEmpty
            ? "no active runs in \(repositories)"
            : "\(counted(active.count, "active run")) in \(Set(active.map(\.repository.id)).count) of \(repositories)"
        let finished = finishedRuns.count
        return finished == 0 ? activity : "\(activity) · \(finished) finished"
    }

    public var activeRuns: [ActiveRun] {
        runs.filter { !$0.isFinished }
    }

    public var finishedRuns: [ActiveRun] {
        runs.filter(\.isFinished)
    }

    /// The unfinished runs waiting for a person or a timer.
    public var waitingRuns: [ActiveRun] {
        runs.filter { $0.run.status == .waiting }
    }
}

/// `1 run`, `2 runs`.
func counted(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
    "\(count) " + (count == 1 ? singular : plural ?? singular + "s")
}
