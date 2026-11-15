/// The symbol and color for a status, so a glance down the left edge tells the story.
struct StatusMark: Sendable, Equatable {
    let symbol: String
    let color: ANSIColor

    static func of(_ status: RunStatus, _ conclusion: Conclusion?) -> StatusMark {
        switch status {
            case .running: StatusMark(symbol: "●", color: .yellow)
            case .queued: StatusMark(symbol: "○", color: .cyan)
            case .pending: StatusMark(symbol: "○", color: .blue)
            case .waiting: StatusMark(symbol: "◇", color: .magenta)
            case .completed: of(conclusion)
            case .unknown: StatusMark(symbol: "?", color: .dim)
        }
    }

    static func of(_ conclusion: Conclusion?) -> StatusMark {
        switch conclusion {
            case .success: StatusMark(symbol: "✓", color: .green)
            case .actionRequired: StatusMark(symbol: "!", color: .yellow)
            case .cancelled: StatusMark(symbol: "⊘", color: .dim)
            case .skipped, .neutral: StatusMark(symbol: "–", color: .dim)
            case let conclusion? where conclusion.isFailure: StatusMark(symbol: "✗", color: .red)
            default: StatusMark(symbol: "•", color: .dim)
        }
    }
}
