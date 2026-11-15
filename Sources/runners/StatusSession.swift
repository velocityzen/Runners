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
    let cache: ResponseCache

    /// Takes one snapshot and prints it.
    func check() async -> Ending {
        status.send(.checking(settings.provider))
        let result = await monitor.snapshot(settings.query)
        cache.save()
        status.send(.checked(result))
        return .finished(result.flatMap(output.render).map { print($0) })
    }

    /// Redraws the screen with a snapshot every interval until cancelled, then clears the
    /// records it made. Saves the response cache after the first snapshot, which pays for
    /// everything, and once more at the end.
    func watch() async -> Ending {
        var records = StatusRecords()
        var saved = false
        for await result in monitor.watch(
            settings.query,
            every: .seconds(settings.display.interval)
        ) {
            Screen.redraw(output.screen(for: result))
            status.send(records.update(result))
            if !saved, result.isSuccess {
                cache.save()
                saved = true
            }
        }
        cache.save()
        status.send(records.clear())
        return .finished(.success(()))
    }
}
