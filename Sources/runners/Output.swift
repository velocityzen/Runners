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

    /// One `--watch` screen: the report, or what went wrong this time.
    func screen(for result: Result<StatusSnapshot, RunnersError>) -> String {
        result.match(screen, screen)
    }

    func screen(_ snapshot: StatusSnapshot) -> String {
        report.render(snapshot)
    }

    func screen(_ error: RunnersError) -> String {
        let time = Date().formatted(date: .omitted, time: .standard)
        return "\(error.localizedDescription)\n\nRetrying… (last attempt \(time))"
    }

    var report: TextReport {
        TextReport(
            style: colored ? .colored : .plain,
            now: Date(),
            showsPassedJobs: showsPassedJobs
        )
    }
}
