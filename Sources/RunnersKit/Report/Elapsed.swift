import Foundation

/// Compact durations: `42s`, `2m 05s`, `1h 03m`, `2d 4h`.
enum Elapsed {
    static func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return switch seconds {
            case ..<60: "\(seconds)s"
            case ..<3_600: "\(seconds / 60)m \(twoDigits(seconds % 60))s"
            case ..<86_400: "\(seconds / 3_600)h \(twoDigits(seconds % 3_600 / 60))m"
            default: "\(seconds / 86_400)d \(seconds % 86_400 / 3_600)h"
        }
    }

    static func between(_ start: Date?, _ end: Date) -> String? {
        start.map { format(end.timeIntervalSince($0)) }
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
