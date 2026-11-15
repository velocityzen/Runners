import Foundation

extension TextReport {
    /// One aligned line per job: mark, name, time, then the runner (or, while queued, the
    /// labels it waits for).
    func jobLines(_ jobs: [Job]) -> [String] {
        let rows = jobs.map(JobRow.init(job:))
        let nameWidth = rows.map(\.name.count).max() ?? 0
        let timeWidth = rows.map { time($0.job).count }.max() ?? 0
        return rows.map { row in
            [
                "    " + mark(StatusMark.of(row.job.status, row.job.conclusion)),
                row.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0),
                time(row.job).padding(toLength: timeWidth, withPad: " ", startingAt: 0),
                style.paint(runner(row.job), .dim),
            ]
            .joined(separator: " ")
            .trimmingTrailingSpaces()
        }
    }

    /// Jobs still going, and finished ones that need a look.
    func visibleJobs(_ jobs: [Job]) -> [Job] {
        showsPassedJobs ? jobs : jobs.filter { !$0.hasPassed }
    }

    /// How long it ran, is running, or has waited.
    func time(_ job: Job) -> String {
        switch job.status {
            case .completed: Elapsed.between(job.startedAt, job.completedAt ?? now) ?? ""
            case .running: Elapsed.between(job.startedAt, now) ?? ""
            default:
                job.status.phrase + (Elapsed.between(job.createdAt, now).map { " \($0)" } ?? "")
        }
    }

    func runner(_ job: Job) -> String {
        switch job.status {
            case .running:
                [job.runner, job.currentStep.map { "→ \($0)" }]
                    .compactMap { $0 }
                    .joined(separator: " ")
            case .completed: job.runner ?? ""
            default: job.labels.joined(separator: ", ")
        }
    }
}

/// A job with its name, prefixed by its stage where there is one, cut to fit a column.
struct JobRow {
    static let maxNameLength = 48

    let job: Job
    let name: String

    init(job: Job) {
        let name = job.stage.map { "\($0) › \(job.name)" } ?? job.name
        self.job = job
        self.name =
            name.count > Self.maxNameLength
            ? name.prefix(Self.maxNameLength - 1) + "…"
            : name
    }
}

extension String {
    func trimmingTrailingSpaces() -> String {
        String(reversed().drop { $0 == " " }.reversed())
    }
}
