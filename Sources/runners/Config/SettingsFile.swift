import Configuration
import FP
import Foundation
import RunnersKit

/// A `.runners` file: one `key=value` per line, with keys named as in the code (`owner`, `all_jobs`,
/// and each provider's own, such as `forge.token`). Lists are comma-separated, `#` starts a
/// comment line, and values may be quoted.
enum SettingsFile {
    /// The settings in the file at `url`. A missing file has none, unless it is `required`.
    static func read(
        _ url: URL,
        required: Bool,
        keys: SettingKeys
    ) -> Result<InMemoryProvider, RunnersError> {
        text(url, required: required)
            .flatMap {
                parse($0, path: url.standardizedFileURL.path(percentEncoded: false), keys: keys)
            }
            .map { provider($0, secret: keys.secret) }
    }

    static func text(_ url: URL, required: Bool) -> Result<String, RunnersError> {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return required ? .failure(.configuration("no file at \(path)")) : .success("")
        }
        return Result { try String(contentsOf: url, encoding: .utf8) }
            .mapError { .configuration("cannot read \(path): \($0.localizedDescription)") }
    }

    /// The settings in `text`; a later line overrides an earlier one with the same key.
    static func parse(
        _ text: String,
        path: String,
        keys: SettingKeys
    ) -> Result<[SettingKey: String], RunnersError> {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .enumerated()
            .map {
                (
                    location: "\(path):\($0.offset + 1)",
                    line: $0.element.trimmingCharacters(in: .whitespaces)
                )
            }
            .filter { !$0.line.isEmpty && !$0.line.hasPrefix("#") }
            .traverse { entry($0.line, at: $0.location, keys: keys) }
            .map { Dictionary($0, uniquingKeysWith: { _, last in last }) }
    }

    static func entry(
        _ line: String,
        at location: String,
        keys: SettingKeys
    ) -> Result<(SettingKey, String), RunnersError> {
        guard let separator = line.firstIndex(of: "=") else {
            return .failure(.configuration("\(location): expected key=value"))
        }
        let name = line[..<separator].trimmingCharacters(in: .whitespaces)
        let value = unquoted(
            line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        )
        return Result.fromOptional(
            keys.key(fileName: name),
            error: unknown(name, at: location, keys: keys)
        )
        .map { ($0, value) }
    }

    static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let quote = value.first, quote == "\"" || quote == "'",
            value.last == quote
        else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    static func unknown(_ name: String, at location: String, keys: SettingKeys) -> RunnersError {
        let known = keys.inFiles.map(\.fileName).joined(separator: ", ")
        return .configuration("\(location): unknown setting \"\(name)\"; the settings are \(known)")
    }

    static func provider(
        _ settings: [SettingKey: String],
        secret: Set<SettingKey>
    ) -> InMemoryProvider {
        InMemoryProvider(
            values: Dictionary(
                uniqueKeysWithValues: settings.map { key, value in
                    (
                        AbsoluteConfigKey(key.configKey),
                        ConfigValue(.string(value), isSecret: secret.contains(key))
                    )
                }
            )
        )
    }
}
