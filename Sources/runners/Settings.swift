import Configuration
import FP
import Foundation
import RunnersKit

/// Where to connect and with what token, from the command line, the environment and `gh`.
struct Settings: Sendable {
    let token: String
    let apiURL: URL
    /// False when `NO_COLOR` is set or standard output is not a terminal.
    let colorAllowed: Bool

    static func load(apiURL override: String?) async -> Result<Settings, GitHubError> {
        let reader = ConfigReader(provider: EnvironmentVariablesProvider())
        return await ResultDo<GitHubError>()
            .bind { apiURL(override ?? reader.string(forKey: "github.api.url")) }
            .bindAsync { url in await token(reader, apiURL: url) }
            .map { url, token in
                Settings(token: token, apiURL: url, colorAllowed: colorAllowed(reader))
            }
    }

    static func apiURL(_ raw: String?) -> Result<URL, GitHubError> {
        guard let raw else { return .success(GitHubClient.defaultBaseURL) }
        return .fromOptional(
            URL(string: raw).flatMap { $0.host() == nil ? nil : $0 },
            error: .invalidURL(raw)
        )
    }

    /// `GH_TOKEN`, then `GITHUB_TOKEN`, then the token of a signed-in `gh`.
    static func token(_ reader: ConfigReader, apiURL: URL) async -> Result<String, GitHubError> {
        let fromEnvironment = ["gh.token", "github.token"]
            .lazy
            .compactMap { reader.string(forKey: ConfigKey($0), isSecret: true) }
            .first { !$0.isEmpty }
        guard let fromEnvironment else {
            return await GHCLI.token(hostname: GHCLI.hostname(forAPI: apiURL))
        }
        return .success(fromEnvironment)
    }

    static func colorAllowed(_ reader: ConfigReader) -> Bool {
        reader.string(forKey: "no.color") == nil && isatty(STDOUT_FILENO) != 0
    }
}
