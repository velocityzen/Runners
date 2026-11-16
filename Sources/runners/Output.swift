import FP
import Foundation
import RunnersKit

/// Turns a snapshot, or the failure to take one, into what gets printed.
struct Output: Sendable {
    let json: Bool
    let colored: Bool
    let showsPassedJobs: Bool

    func render(_ snapshot: StatusSnapshot) -> Result<String, RunnersError> {
        json ? snapshot.json() : .success(report.render(snapshot))
    }

    /// One `--watch` screen: the report. When this refresh failed, the last report stays, with
    /// what went wrong beneath it; before there is one, only what went wrong shows.
    func screen(
        for result: Result<StatusSnapshot, RunnersError>,
        shown: StatusSnapshot?,
        at now: Date = Date()
    ) -> String {
        result.match(
            { report(at: now).render($0) },
            { error in
                shown.map { report(at: now).render($0, refreshFailed: error, lastAttempt: now) }
                    ?? screen(error, at: now)
            }
        )
    }

    func screen(_ error: RunnersError, at now: Date) -> String {
        let time = now.formatted(date: .omitted, time: .standard)
        return "\(error.localizedDescription)\n\nRetrying… (last attempt \(time))"
    }

    var report: TextReport {
        report(at: Date())
    }

    func report(at now: Date) -> TextReport {
        TextReport(
            style: colored ? .colored : .plain,
            now: now,
            showsPassedJobs: showsPassedJobs
        )
    }
}
