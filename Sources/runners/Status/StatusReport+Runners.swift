import Foundation
import ProgramStatus
import RunnersKit

/// What `runners` tells the terminal through the Program Status Protocol (OSC 7501).
///
/// The root record stands for the whole check. With `--watch`, each repository on screen gets a
/// record, with one per run beneath it; a finished run's record keeps how it ended.
extension StatusReport {
    /// The root record while a one-off check runs.
    static func checking(_ provider: any Provider) -> StatusReport {
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
        return snapshot.activeRuns.isEmpty ? .idle(text) : .working(text)
    }

    /// The root record while a one-off list of runners is read.
    static func checkingRunners(_ provider: any Provider) -> StatusReport {
        .working("Checking runners on \(provider.name)")
    }

    static func checkedRunners(_ result: Result<RunnersSnapshot, RunnersError>) -> StatusReport {
        result.match(
            { .done(message(sentence($0))) },
            failed
        )
    }

    /// The root record while watching runners: working while any is busy, idle otherwise.
    static func watching(_ snapshot: RunnersSnapshot) -> StatusReport {
        let text = message(sentence(snapshot))
        return snapshot.runners.contains { $0.state == .busy } ? .working(text) : .idle(text)
    }

    static func failed(_ error: RunnersError) -> StatusReport {
        .error(message(error.localizedDescription))
    }

    /// The root record once the user stops `runners`.
    static let stopped = StatusReport.idle("Stopped")

    /// Blocked while a run waits, working while runs are active, then error if a finished run
    /// failed, or done.
    static func repository(_ group: RepositoryRuns) -> StatusReport {
        let id = recordID(group.repository.id)
        let title = title(group.repository.fullName)
        let active = group.runs.filter { !$0.isFinished }
        let waiting = active.count { $0.run.status == .waiting }
        let failed = group.runs.count { $0.isFinished && $0.run.conclusion?.isFailure == true }
        let finished = group.runs.count - active.count
        let text = message([
            waiting > 0 ? "\(waiting) of \(active.count) waiting" : nil,
            waiting == 0 && !active.isEmpty ? "\(active.count) active" : nil,
            failed > 0 ? "\(failed) failed" : nil,
            finished > failed ? "\(finished - failed) finished" : nil,
        ])
        if waiting > 0 { return .blocked(text, kind: .permission, id: id, title: title) }
        if !active.isEmpty { return .working(text, id: id, title: title) }
        return failed > 0 ? .error(text, id: id, title: title) : .done(text, id: id, title: title)
    }

    static func run(_ active: ActiveRun) -> StatusReport {
        let run = active.run
        let phrase = active.isFinished ? run.conclusion?.phrase ?? "finished" : run.status.phrase
        return StatusReport(
            state: state(active),
            id: recordID(active.repository.id, run.id),
            title: title([run.name, run.number.map { "#\($0)" }]),
            message: message([phrase, run.branch, run.title])
        )
    }

    static func state(_ active: ActiveRun) -> State {
        switch active.run.status {
            case .waiting: .blocked(kind: .permission, progress: progress(active.jobs))
            case .running: .working(progress: progress(active.jobs))
            case .completed: finished(active.run.conclusion)
            default: .working()
        }
    }

    /// Done when it passed, error when it failed, idle when cancelled, blocked when it needs
    /// approval to go on.
    static func finished(_ conclusion: Conclusion?) -> State {
        switch conclusion {
            case .actionRequired: .blocked(kind: .permission)
            case .cancelled: .idle
            case let conclusion? where conclusion.isFailure: .error
            default: .done
        }
    }

    /// The share of jobs finished, when the run's jobs are known.
    static func progress(_ jobs: [Job]?) -> Int? {
        guard let jobs, !jobs.isEmpty else { return nil }
        return jobs.filter { $0.status == .completed }.count * 100 / jobs.count
    }
}
