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

    /// `octo on GitHub · 2 active runs in 1 of 12 repositories · 10:42:13`
    func header(_ snapshot: StatusSnapshot) -> String {
        let term = snapshot.provider.repositoryTerm
        let repositories = plural(snapshot.repositoryCount, term.singular, term.plural)
        let counts =
            snapshot.runs.isEmpty
            ? "no active runs in \(repositories)"
            : "\(plural(snapshot.runs.count, "active run")) in \(snapshot.byRepository.count) of \(repositories)"
        let time = snapshot.fetchedAt.formatted(date: .omitted, time: .standard)
        let scope =
            snapshot.owner.map { "\($0.login) on \(snapshot.provider.name)" }
            ?? snapshot.provider.name
        return style.paint(scope, .bold) + style.paint(" · \(counts) · \(time)", .dim)
    }

    func body(_ snapshot: StatusSnapshot) -> [String] {
        snapshot.byRepository.flatMap(repositoryLines)
    }

    func footer(_ snapshot: StatusSnapshot) -> [String] {
        guard let limit = snapshot.rateLimit else { return [] }
        let reset = limit.resetAt.formatted(date: .omitted, time: .shortened)
        let text =
            "API quota \(limit.remaining.formatted())/\(limit.limit.formatted()) · resets \(reset)"
        return ["", style.paint(text, .dim)]
    }

    func repositoryLines(_ group: RepositoryRuns) -> [String] {
        ["", style.paint(group.repository.fullName, .bold)] + group.runs.flatMap(runLines)
    }

    func plural(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count) " + (count == 1 ? singular : plural ?? singular + "s")
    }
}
