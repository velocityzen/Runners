import Foundation

extension TextReport {
    /// One aligned line per job: mark, name, time, then the runner (or, while queued, the
    /// labels it waits for).
    func jobLines(_ jobs: [WorkflowJob]) -> [String] {
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
    func visibleJobs(_ jobs: [WorkflowJob]) -> [WorkflowJob] {
        showsPassedJobs ? jobs : jobs.filter { !$0.hasPassed }
    }

    /// How long it ran, is running, or has waited.
    func time(_ job: WorkflowJob) -> String {
        switch job.status {
            case .completed: Elapsed.between(job.startedAt, job.completedAt ?? now) ?? ""
            case .inProgress: Elapsed.between(job.startedAt, now) ?? ""
            default: job.status.phrase + (Elapsed.between(job.createdAt, now).map { " \($0)" } ?? "")
        }
    }

    func runner(_ job: WorkflowJob) -> String {
        switch job.status {
            case .inProgress:
                [job.runnerName, job.currentStep.map { "→ \($0.name)" }]
                    .compactMap { $0 }
                    .joined(separator: " ")
            case .completed: job.runnerName ?? ""
            default: job.labels.joined(separator: ", ")
        }
    }
}

/// A job with its name cut to fit a column.
struct JobRow {
    static let maxNameLength = 48

    let job: WorkflowJob
    let name: String

    init(job: WorkflowJob) {
        self.job = job
        self.name =
            job.name.count > Self.maxNameLength
            ? job.name.prefix(Self.maxNameLength - 1) + "…"
            : job.name
    }
}

extension WorkflowJob {
    /// Finished with nothing to look at.
    var hasPassed: Bool {
        status == .completed && [.success, .skipped, .neutral].contains(conclusion)
    }
}

extension String {
    func trimmingTrailingSpaces() -> String {
        String(reversed().drop { $0 == " " }.reversed())
    }
}
