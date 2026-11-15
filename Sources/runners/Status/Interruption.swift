import FP
import Foundation
import ProcessSignals
import RunnersKit

/// How a command ended: on its own, or stopped by the user.
enum Ending: Sendable {
    case finished(Result<Void, RunnersError>)
    case interrupted(signal: Int32)
}

/// Runs work until it ends, or until the process gets SIGINT (Ctrl-C) or SIGTERM.
enum Interruption {
    /// The signals stream ended without a signal: it was cancelled, or could not subscribe.
    struct NoSignal: Error {}

    static let signals = [SIGINT, SIGTERM]

    /// Whichever ends first: the work, or a signal. The other is cancelled, and this returns
    /// once it stops, so the work can clean up after a signal.
    static func race(
        _ work: @concurrent @Sendable @escaping () async -> Ending,
        until signals: AsyncStream<Int32>
    ) async -> Ending {
        await withAny(
            await Result<Ending, NoSignal>.success(work()),
            await first(of: signals)
        )
        // Only the signals can fail, so the work always gives a value.
        .getOrElse { _ in .finished(.success(())) }
    }

    /// The first signal; a failure, which never wins the race, if the stream ends first.
    static func first(of signals: AsyncStream<Int32>) async -> Result<Ending, NoSignal> {
        for await signal in signals {
            return .success(.interrupted(signal: signal))
        }
        return .failure(NoSignal())
    }
}
