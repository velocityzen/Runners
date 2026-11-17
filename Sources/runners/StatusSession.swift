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
    /// Shows the runners instead of the runs.
    var listsRunners = false

    /// Takes one snapshot and prints it.
    func check() async -> Ending {
        listsRunners ? await checkRunners() : await checkRuns()
    }

    /// Redraws the screen with a new snapshot until cancelled.
    func watch() async -> Ending {
        listsRunners ? await watchRunners() : await watchRuns()
    }

    func checkRuns() async -> Ending {
        status.send(.checking(settings.provider))
        let result = await monitor.snapshot(settings.query)
        cache.save()
        status.send(.checked(result))
        return .finished(result.flatMap(output.render).map { print($0) })
    }

    /// Redraws the screen with a new snapshot, the interval after the last one finished, until
    /// cancelled, then clears the records it made. A failed refresh, such as while offline,
    /// leaves the last snapshot on screen with the failure beneath it. Saves the response cache
    /// after the first snapshot, which pays for everything, and once more at the end.
    func watchRuns() async -> Ending {
        var records = StatusRecords()
        var saved = false
        var shown: StatusSnapshot?

        for await result in monitor.watch(
            settings.query,
            every: .seconds(settings.display.interval)
        ) {
            Screen.redraw(output.screen(for: result, shown: shown))
            shown = (try? result.get()) ?? shown
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

    /// Lists the runners once.
    func checkRunners() async -> Ending {
        status.send(.checkingRunners(settings.provider))
        let result = await monitor.runners(settings.query)
        cache.save()
        status.send(.checkedRunners(result))
        return .finished(result.flatMap(output.render).map { print($0) })
    }

    /// Redraws the runners until cancelled, keeping the last list on screen when a refresh
    /// fails. Only the root record goes to the terminal.
    func watchRunners() async -> Ending {
        var records = StatusRecords()
        var saved = false
        var shown: RunnersSnapshot?

        for await result in monitor.watchRunners(
            settings.query,
            every: .seconds(settings.display.interval)
        ) {
            Screen.redraw(output.screen(forRunners: result, shown: shown))
            shown = (try? result.get()) ?? shown
            status.send(records.update(runners: result))
            if !saved, result.isSuccess {
                cache.save()
                saved = true
            }
        }
        cache.save()
        return .finished(.success(()))
    }
}
