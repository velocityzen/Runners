import FP
import Foundation

extension TextReport {
    /// ```
    ///   ● CI #142  Fix flaky test
    ///     running 2m 13s · main · push · @octocat · 1/3 jobs done
    ///     https://github.com/octo/repo/actions/runs/1
    ///     ● test    1m 11s  runner-13 → Run tests
    ///     ○ deploy  queued 2m 13s  ubuntu-latest
    /// ```
    func runLines(_ active: ActiveRun) -> [String] {
        let run = active.run
        return [
            "  " + mark(StatusMark.of(run.status, run.conclusion)) + " " + title(run),
            "    " + style.paint(details(active), .dim),
            "    " + style.paint(run.webURL.absoluteString, .dim),
        ] + jobLines(visibleJobs(active.jobs ?? []))
    }

    func title(_ run: Run) -> String {
        let number = run.number.map { " #\($0)" } ?? ""
        let attempt = (run.attempt ?? 1) > 1 ? " (attempt \(run.attempt ?? 1))" : ""
        let name = style.paint(run.name + number + attempt, .bold)
        return [name, run.title].compact().joined(separator: "  ")
    }

    func details(_ active: ActiveRun) -> String {
        let run = active.run
        return [
            state(run),
            run.branch,
            run.trigger,
            run.actor.map { "@\($0)" },
            active.jobs.flatMap(progress),
        ]
        .compact()
        .joined(separator: " · ")
    }

    /// `running 2m 13s`, `queued 5s`; for a finished run `success in 3m 12s, 2m ago`.
    func state(_ run: Run) -> String {
        guard run.status == .completed else {
            let since = run.status == .running ? run.startedAt ?? run.createdAt : run.createdAt
            return "\(run.status.phrase) \(Elapsed.format(now.timeIntervalSince(since)))"
        }
        let outcome = run.conclusion?.phrase ?? "finished"
        guard let completedAt = run.completedAt else { return outcome }
        let took =
            Elapsed.between(run.startedAt ?? run.createdAt, completedAt).map { " in \($0)" } ?? ""
        return "\(outcome)\(took), \(Elapsed.format(now.timeIntervalSince(completedAt))) ago"
    }

    /// `7/12 jobs done`, or nothing before any job exists.
    func progress(_ jobs: [Job]) -> String? {
        guard !jobs.isEmpty else { return nil }
        let done = jobs.count { $0.status == .completed }
        return "\(done)/\(jobs.count) jobs done"
    }

    func mark(_ mark: StatusMark) -> String {
        style.paint(mark.symbol, mark.color)
    }
}
