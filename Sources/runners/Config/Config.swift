import Configuration
import FP
import RunnersKit

/// Settings from every source, earliest first. The first source that sets a key decides its value.
struct Config: Sendable {
    let sources: [ConfigReader]

    /// The first value set for any of `keys`, and which key set it. Within a source, earlier keys win.
    func text(_ keys: [SettingKey], isSecret: Bool = false) -> (key: SettingKey, value: String)? {
        sources.lazy
            .compactMap { source in
                keys.lazy
                    .compactMap { key in source.text(key, isSecret: isSecret).map { (key, $0) } }
                    .first
            }
            .first
    }

    func text(_ key: SettingKey) -> String? {
        text([key])?.value
    }

    func list(_ key: SettingKey) -> [String] {
        sources.lazy.map { $0.list(key) }.first { !$0.isEmpty } ?? []
    }

    /// The given value when there is one, else the configured one, else the fallback.
    func value<Value>(
        _ given: Value?,
        _ key: SettingKey,
        default fallback: @autoclosure () -> Value,
        expected: String,
        parse: (String) -> Value?
    ) -> Result<Value, RunnersError> {
        if let given { return .success(given) }
        guard let raw = text(key) else { return .success(fallback()) }
        return .fromOptional(parse(raw), error: key.invalid(raw, expected: expected))
    }

    func flag(_ given: Bool?, _ key: SettingKey, default fallback: @autoclosure () -> Bool)
        -> Result<Bool, RunnersError>
    {
        value(given, key, default: fallback(), expected: "true or false", parse: Self.bool)
    }

    func number(_ given: Int?, _ key: SettingKey, default fallback: Int, in range: ClosedRange<Int>)
        -> Result<Int, RunnersError>
    {
        value(
            given,
            key,
            default: fallback,
            expected: "a whole number from \(range.lowerBound) to \(range.upperBound)"
        ) {
            Int($0).flatMap { range.contains($0) ? $0 : nil }
        }
    }

    static func bool(_ raw: String) -> Bool? {
        switch raw.lowercased() {
            case "true", "yes", "on", "1": true
            case "false", "no", "off", "0": false
            default: nil
        }
    }
}

extension ConfigReader {
    /// The key's value without surrounding whitespace; nil when unset or blank.
    func text(_ key: SettingKey, isSecret: Bool = false) -> String? {
        string(forKey: key.configKey, isSecret: isSecret)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A comma-separated list.
    func list(_ key: SettingKey) -> [String] {
        (text(key) ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
