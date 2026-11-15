import Configuration
import RunnersKit

/// The name of a setting.
///
/// The environment and `.env` spell it in capitals with underscores: `RUNNERS_ALL_JOBS`, and a
/// provider's `forge.token` as `FORGE_TOKEN`. `.runners` files spell it as here, without the
/// `runners.` prefix: `all_jobs`, `forge.token`.
struct SettingKey: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    let name: String

    init(stringLiteral name: String) {
        self.name = name
    }

    init(_ setting: ProviderSetting) {
        name = setting.name
    }

    var configKey: ConfigKey {
        ConfigKey(name)
    }

    var environmentName: String {
        String(name.uppercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }

    var fileName: String {
        name.hasPrefix(Self.prefix) ? String(name.dropFirst(Self.prefix.count)) : name
    }

    var description: String {
        "\(fileName) (\(environmentName))"
    }

    /// The failure for a value this setting cannot take.
    func invalid(_ value: String, expected: String) -> RunnersError {
        .configuration("\(self) is \"\(value)\", expected \(expected)")
    }

    private static let prefix = "runners."
}

extension SettingKey {
    static let provider: SettingKey = "runners.provider"
    static let owner: SettingKey = "runners.owner"
    static let repositories: SettingKey = "runners.repos"
    static let status: SettingKey = "runners.status"
    static let jobs: SettingKey = "runners.jobs"
    static let allJobs: SettingKey = "runners.all_jobs"
    static let forks: SettingKey = "runners.forks"
    static let concurrency: SettingKey = "runners.concurrency"
    static let interval: SettingKey = "runners.interval"
    static let color: SettingKey = "runners.color"
    static let programStatus: SettingKey = "runners.program_status"
    static let cache: SettingKey = "runners.cache"
    static let noColor: SettingKey = "no_color"

    /// The settings of `runners` itself that a `.runners` file may set; each provider adds its
    /// own. `no_color` is another tool's convention, so only the environment sets it.
    static let common: [SettingKey] = [
        .provider, .owner, .repositories, .status, .jobs, .allJobs, .forks, .concurrency, .interval,
        .color, .programStatus, .cache,
    ]
}
