import Foundation

/// Renders a snapshot for the terminal: one block per repository, one line per job.
public struct TextReport: Sendable {
    public let style: TerminalStyle
    public let now: Date
    /// List jobs that finished without trouble too; by default only their count shows.
    public let showsPassedJobs: Bool

    public init(style: TerminalStyle = .plain, now: Date = Date(), showsPassedJobs: Bool = false) {
        self.style = style
        self.now = now
        self.showsPassedJobs = showsPassedJobs
    }

    public func render(_ snapshot: StatusSnapshot) -> String {
        ([header(snapshot)] + body(snapshot) + footer(snapshot))
            .joined(separator: "\n")
    }

    /// The last snapshot once a refresh has failed: as it was when it was taken, so its times
    /// stop instead of running on, with what went wrong beneath it.
    public func render(
        _ snapshot: StatusSnapshot,
        refreshFailed error: RunnersError,
        lastAttempt: Date
    ) -> String {
        let asTaken = TextReport(
            style: style,
            now: snapshot.fetchedAt,
            showsPassedJobs: showsPassedJobs
        )
        return
            ([asTaken.render(snapshot), ""]
            + failedRefresh(error, shownAt: snapshot.fetchedAt, lastAttempt: lastAttempt))
            .joined(separator: "\n")
    }

    /// `⚠ Network error: …`, then
    /// `Showing the runs as of 10:42:13 · retrying, last attempt 10:43:01`
    func failedRefresh(
        _ error: RunnersError,
        shownAt: Date,
        lastAttempt: Date,
        showing: String = "runs"
    ) -> [String] {
        let shown = shownAt.formatted(date: .omitted, time: .standard)
        let attempt = lastAttempt.formatted(date: .omitted, time: .standard)
        return [
            style.paint("⚠ \(error.localizedDescription)", .yellow),
            style.paint(
                "Showing the \(showing) as of \(shown) · retrying, last attempt \(attempt)",
                .dim
            ),
        ]
    }

    /// `octo on GitHub · 2 active runs in 1 of 12 repositories · 10:42:13`
    func header(_ snapshot: StatusSnapshot) -> String {
        let time = snapshot.fetchedAt.formatted(date: .omitted, time: .standard)
        return style.paint(snapshot.scope, .bold)
            + style.paint(" · \(snapshot.summary) · \(time)", .dim)
    }

    func body(_ snapshot: StatusSnapshot) -> [String] {
        snapshot.byRepository.flatMap(repositoryLines)
    }

    func footer(_ snapshot: StatusSnapshot) -> [String] {
        footer(snapshot.rateLimit)
    }

    /// `API quota 4,321/5,000 · resets 11:00`, after a blank line.
    func footer(_ rateLimit: RateLimit?) -> [String] {
        guard let limit = rateLimit else { return [] }
        let reset = limit.resetAt.formatted(date: .omitted, time: .shortened)
        let text =
            "API quota \(limit.remaining.formatted())/\(limit.limit.formatted()) · resets \(reset)"
        return ["", style.paint(text, .dim)]
    }

    func repositoryLines(_ group: RepositoryRuns) -> [String] {
        ["", style.paint(group.repository.fullName, .bold)] + group.runs.flatMap(runLines)
    }
}
