import RunnersKit

/// How a command ended: on its own, or stopped by the user.
enum Ending: Sendable {
    case finished(Result<Void, RunnersError>)
    case interrupted(signal: Int32)
}
