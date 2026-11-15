extension StatusSnapshot {
    /// Whose runs these are: `octo on GitHub`, or just `GitHub` for a list of repositories.
    public var scope: String {
        owner.map { "\($0.login) on \(provider.name)" } ?? provider.name
    }

    /// `2 active runs in 1 of 12 repositories`, or `no active runs in 12 repositories`.
    public var summary: String {
        let term = provider.repositoryTerm
        let repositories = counted(repositoryCount, term.singular, term.plural)
        guard !runs.isEmpty else { return "no active runs in \(repositories)" }
        return "\(counted(runs.count, "active run")) in \(byRepository.count) of \(repositories)"
    }

    /// The runs waiting for a person or a timer.
    public var waitingRuns: [ActiveRun] {
        runs.filter { $0.run.status == .waiting }
    }
}

/// `1 run`, `2 runs`.
func counted(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
    "\(count) " + (count == 1 ? singular : plural ?? singular + "s")
}
