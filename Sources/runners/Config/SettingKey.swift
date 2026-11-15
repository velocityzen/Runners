import Configuration
import RunnersKit

/// The name of a setting.
///
/// The environment and `.env` spell it in capitals with underscores: `RUNNERS_ALL_JOBS`, `GITHUB_TOKEN`.
/// `.runners` files spell it as here, without the `runners.` prefix: `all_jobs`, `github.token`.
struct SettingKey: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    let name: String

    init(stringLiteral name: String) {
        self.name = name
    }

    /// The key a `.runners` file spells this way.
    init?(fileName: String) {
        guard let key = Self.fileKeys.first(where: { $0.fileName == fileName }) else { return nil }
        self = key
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

    var isSecret: Bool {
        name.hasSuffix("token")
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
    static let noColor: SettingKey = "no_color"

    static let ghToken: SettingKey = "gh.token"
    static let gitHubToken: SettingKey = "github.token"
    static let gitHubAPIURL: SettingKey = "github.api_url"

    static let gitLabToken: SettingKey = "gitlab.token"
    static let gitLabAccessToken: SettingKey = "gitlab.access_token"
    static let gitLabHost: SettingKey = "gitlab.host"
    static let gitLabCIAPIURL: SettingKey = "ci.api_v4_url"

    /// What a `.runners` file may set. The other keys are environment conventions of other tools.
    static let fileKeys: [SettingKey] = [
        .provider, .owner, .repositories, .status, .jobs, .allJobs, .forks, .concurrency, .interval,
        .color, .programStatus,
        .gitHubToken, .gitHubAPIURL, .gitLabToken, .gitLabHost,
    ]
}
