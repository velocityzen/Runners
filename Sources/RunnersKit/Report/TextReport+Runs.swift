import Foundation

extension TextReport {
    /// ```
    ///   ● CI #142  Fix flaky test
    ///     running 2m 13s · main · push · @octocat · 1/3 jobs done
    ///     https://github.com/octo/repo/actions/runs/1
    ///     ● test    1m 11s  GitHub Actions 13 → Run tests
    ///     ○ deploy  queued 2m 13s  ubuntu-latest
    /// ```
    func runLines(_ active: ActiveRun) -> [String] {
        let run = active.run
        return [
            "  " + mark(StatusMark.of(run.status, run.conclusion)) + " " + title(run),
            "    " + style.paint(details(active), .dim),
            "    " + style.paint(run.htmlURL.absoluteString, .dim),
        ] + jobLines(visibleJobs(active.jobs ?? []))
    }

    func title(_ run: WorkflowRun) -> String {
        let attempt = (run.runAttempt ?? 1) > 1 ? " (attempt \(run.runAttempt ?? 1))" : ""
        let name = style.paint("\(run.name ?? "Workflow") #\(run.runNumber)\(attempt)", .bold)
        return [name, run.displayTitle].compactMap { $0 }.joined(separator: "  ")
    }

    func details(_ active: ActiveRun) -> String {
        let run = active.run
        let since = run.status == .inProgress ? run.runStartedAt ?? run.createdAt : run.createdAt
        return [
            "\(run.status.phrase) \(Elapsed.format(now.timeIntervalSince(since)))",
            run.headBranch,
            run.event,
            run.actor.map { "@\($0.login)" },
            active.jobs.flatMap(progress),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    /// `7/12 jobs done`, or nothing before any job exists.
    func progress(_ jobs: [WorkflowJob]) -> String? {
        guard !jobs.isEmpty else { return nil }
        let done = jobs.count { $0.status == .completed }
        return "\(done)/\(jobs.count) jobs done"
    }

    func mark(_ mark: StatusMark) -> String {
        style.paint(mark.symbol, mark.color)
    }
}
