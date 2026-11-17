import Foundation

extension TextReport {
    /// The runners grouped by state, busy first, one aligned line each, then what was left
    /// out.
    public func render(_ snapshot: RunnersSnapshot) -> String {
        let width = snapshot.runners.map(\.name.count).max() ?? 0
        let groups = snapshot.byState.flatMap { group in
            ["", style.paint(group.state.title, .bold)]
                + group.runners.map { runnerLine($0, nameWidth: width) }
        }
        let notes =
            snapshot.notes.isEmpty ? [] : [""] + snapshot.notes.map { style.paint($0, .dim) }
        return ([header(snapshot)] + groups + notes + footer(snapshot.rateLimit))
            .joined(separator: "\n")
    }

    /// The last runners snapshot once a refresh has failed, with what went wrong beneath it.
    public func render(
        _ snapshot: RunnersSnapshot,
        refreshFailed error: RunnersError,
        lastAttempt: Date
    ) -> String {
        ([render(snapshot), ""]
            + failedRefresh(
                error,
                shownAt: snapshot.fetchedAt,
                lastAttempt: lastAttempt,
                showing: "runners"
            ))
            .joined(separator: "\n")
    }

    /// `acme on GitHub · 5 runners, 2 busy · 10:42:13`
    func header(_ snapshot: RunnersSnapshot) -> String {
        let time = snapshot.fetchedAt.formatted(date: .omitted, time: .standard)
        return style.paint(snapshot.scope, .bold)
            + style.paint(" · \(snapshot.summary) · \(time)", .dim)
    }

    /// `  ● mac-mini-1 macOS · self-hosted, macOS, ARM64 → build (acme/app)`
    func runnerLine(_ runner: Runner, nameWidth: Int) -> String {
        [
            "  " + mark(RunnerMark.of(runner.state)),
            runner.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0),
            style.paint(about(runner), .dim),
        ]
        .joined(separator: " ")
        .trimmingTrailingSpaces()
    }

    /// Why it is offline, what it is and runs on, then the jobs it is on.
    func about(_ runner: Runner) -> String {
        let facts = [
            runner.state == .offline ? runner.status.phrase : nil,
            runner.paused && runner.state != .paused ? "paused" : nil,
            runner.kind.phrase,
            runner.host?.name,
            runner.details,
            runner.labels.isEmpty ? nil : runner.labels.joined(separator: ", "),
            runner.ephemeral ? "ephemeral" : nil,
        ]
        .compactMap(\.self)
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        return [facts, jobs(runner.jobs)].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// `→ build (acme/app) +1 more`
    func jobs(_ jobs: [RunnerJob]) -> String {
        guard let first = jobs.first else { return "" }
        let job = first.repository.map { "\(first.name) (\($0))" } ?? first.name
        return "→ \(job)" + (jobs.count > 1 ? " +\(jobs.count - 1) more" : "")
    }
}

extension Runner.State {
    /// `Busy`
    var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

extension Runner.Kind {
    /// What the report says about the kind, when it says something the reader can't tell.
    var phrase: String? {
        switch self {
            case .selfHosted: nil
            case .githubHosted: "GitHub-hosted"
            case .instance: "instance runner"
            case .group: "group runner"
            case .project: "project runner"
        }
    }
}

/// The symbol and color for a runner's state.
enum RunnerMark {
    static func of(_ state: Runner.State) -> StatusMark {
        switch state {
            case .busy: StatusMark(symbol: "●", color: .yellow)
            case .idle: StatusMark(symbol: "○", color: .green)
            case .paused: StatusMark(symbol: "‖", color: .dim)
            case .offline: StatusMark(symbol: "✗", color: .red)
        }
    }
}
