/// Colors text with ANSI escape codes, or leaves it plain.
public struct TerminalStyle: Sendable, Equatable {
    public let isColored: Bool

    public init(isColored: Bool) {
        self.isColored = isColored
    }

    public static let plain = TerminalStyle(isColored: false)
    public static let colored = TerminalStyle(isColored: true)

    func paint(_ text: String, _ color: ANSIColor) -> String {
        isColored && !text.isEmpty ? "\u{1B}[\(color.rawValue)m\(text)\u{1B}[0m" : text
    }
}

enum ANSIColor: String, Sendable {
    case bold = "1"
    case dim = "2"
    case red = "31"
    case green = "32"
    case yellow = "33"
    case blue = "34"
    case magenta = "35"
    case cyan = "36"
}
