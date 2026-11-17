import ProgramStatus
import RunnersKit

/// Fitting values into what a report accepts.
extension StatusReport {
    static let titleBytes = 192
    static let messageBytes = 2048
    static let segmentLength = 32

    /// `octo on GitHub: 2 active runs in 1 of 12 repositories`
    static func sentence(_ snapshot: StatusSnapshot) -> String {
        "\(snapshot.scope): \(snapshot.summary)"
    }

    /// `acme on GitHub: 5 runners, 2 busy`
    static func sentence(_ snapshot: RunnersSnapshot) -> String {
        "\(snapshot.scope): \(snapshot.summary)"
    }

    static func title(_ parts: [String?]) -> String {
        title(parts.compactMap(\.self).joined(separator: " "))
    }

    static func title(_ text: String) -> String {
        fitted(text, bytes: titleBytes)
    }

    static func message(_ parts: [String?]) -> String {
        message(parts.compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · "))
    }

    static func message(_ text: String) -> String {
        fitted(text, bytes: messageBytes)
    }

    /// On one line, cut at a character so it takes at most `bytes` of UTF-8.
    static func fitted(_ text: String, bytes: Int) -> String {
        var fitted = ""
        var used = 0
        for character in StatusText.singleLine(text) {
            used += character.utf8.count
            guard used <= bytes else { break }
            fitted.append(character)
        }
        return fitted
    }

    /// A record path from ids, each made a valid segment: `[A-Za-z0-9_.+-]{1,32}`.
    static func recordID(_ ids: String...) -> String {
        ids.map(segment).joined(separator: "/")
    }

    static func segment(_ id: String) -> String {
        let cleaned = id.unicodeScalars.map { isSegmentScalar($0) ? Character($0) : "_" }
        return cleaned.isEmpty ? "_" : String(cleaned.suffix(segmentLength))
    }

    static func isSegmentScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", "_", ".", "+", "-": true
            default: false
        }
    }
}
