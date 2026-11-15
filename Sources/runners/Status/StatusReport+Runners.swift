import Foundation
import ProgramStatus
import RunnersKit

/// What `runners` tells the terminal through the Program Status Protocol (OSC 7501).
///
/// The root record stands for the whole check. With `--watch`, each repository with active
/// runs gets a record, with one per run beneath it.
extension StatusReport {
    /// The root record while a one-off check runs.
    static func checking(_ provider: Provider) -> StatusReport {
        .working("Checking CI runs on \(provider.name)")
    }

    /// The root record when a one-off check ends.
    static func checked(_ result: Result<StatusSnapshot, RunnersError>) -> StatusReport {
        result.match(
            { .done(message(sentence($0))) },
            failed
        )
    }

    /// The root record while watching: blocked while a run waits for approval, working while
    /// runs are active, idle when none are.
    static func watching(_ snapshot: StatusSnapshot) -> StatusReport {
        let text = message(sentence(snapshot))
        if !snapshot.waitingRuns.isEmpty { return .blocked(text, kind: .permission) }
        return snapshot.runs.isEmpty ? .idle(text) : .working(text)
    }

    static func failed(_ error: RunnersError) -> StatusReport {
        .error(message(error.localizedDescription))
    }

    /// The root record once the user stops `runners`.
    static let stopped = StatusReport.idle("Stopped")

    static func repository(_ group: RepositoryRuns) -> StatusReport {
        let waiting = group.runs.filter { $0.run.status == .waiting }.count
        let text = message(
            waiting > 0 ? "\(waiting) of \(group.runs.count) waiting" : "\(group.runs.count) active"
        )
        let id = recordID(group.repository.id)
        let title = title(group.repository.fullName)
        return waiting > 0
            ? .blocked(text, kind: .permission, id: id, title: title)
            : .working(text, id: id, title: title)
    }

    static func run(_ active: ActiveRun) -> StatusReport {
        StatusReport(
            state: state(active),
            id: recordID(active.repository.id, active.run.id),
            title: title([active.run.name, active.run.number.map { "#\($0)" }]),
            message: message([active.run.status.phrase, active.run.branch, active.run.title])
        )
    }

    static func state(_ active: ActiveRun) -> State {
        switch active.run.status {
            case .waiting: .blocked(kind: .permission, progress: progress(active.jobs))
            case .running: .working(progress: progress(active.jobs))
            default: .working()
        }
    }

    /// The share of jobs finished, when the run's jobs are known.
    static func progress(_ jobs: [Job]?) -> Int? {
        guard let jobs, !jobs.isEmpty else { return nil }
        return jobs.filter { $0.status == .completed }.count * 100 / jobs.count
    }
}
