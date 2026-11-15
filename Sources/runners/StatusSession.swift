import FP
import Foundation
import ProgramStatus
import RunnersKit

/// One `runners status`: a check, or a watch, shown on screen and reported to the terminal.
struct StatusSession: Sendable {
    let monitor: RunsMonitor
    let settings: Settings
    let output: Output
    let status: TerminalStatus

    /// Takes one snapshot and prints it.
    func check() async -> Ending {
        status.send(.checking(settings.provider))
        let result = await monitor.snapshot(settings.query)
        status.send(.checked(result))
        return .finished(result.flatMap(output.render).map { print($0) })
    }

    /// Redraws the screen with a snapshot every interval until cancelled, then clears the
    /// records it made.
    func watch() async -> Ending {
        var records = StatusRecords()
        for await result in monitor.watch(
            settings.query,
            every: .seconds(settings.display.interval)
        ) {
            Screen.redraw(output.screen(for: result))
            status.send(records.update(result))
        }
        status.send(records.clear())
        return .finished(.success(()))
    }
}
