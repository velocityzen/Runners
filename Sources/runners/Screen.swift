import Foundation

/// The terminal, redrawn in place for `--watch`.
enum Screen {
    static let clear = "\u{1B}[H\u{1B}[2J\u{1B}[3J"

    /// Replaces what is on screen. Written in one piece, unbuffered, so a pipe sees each screen
    /// as it is drawn.
    static func redraw(_ text: String) {
        FileHandle.standardOutput.write(Data((clear + text + "\n").utf8))
    }
}
