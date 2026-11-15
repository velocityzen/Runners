import Foundation

/// Redraws the screen with fresh output, forever.
struct Watch {
    static let clearScreen = "\u{1B}[H\u{1B}[2J\u{1B}[3J"

    let interval: Duration
    let refresh: () async -> String

    func run() async throws {
        while true {
            let screen = await refresh()
            // Written in one piece, unbuffered, so a pipe sees each screen as it is drawn.
            FileHandle.standardOutput.write(Data((Self.clearScreen + screen + "\n").utf8))
            try await Task.sleep(for: interval)
        }
    }
}
