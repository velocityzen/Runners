import FP
import Foundation
import RunnersKit

/// Where each service's token and API URL come from, and how to build the service.
extension Provider {
    /// Keys holding a token. In each source the first one set wins.
    var tokenKeys: [SettingKey] {
        switch self {
            case .github: [.ghToken, .gitHubToken]
            case .gitlab: [.gitLabToken, .gitLabAccessToken]
        }
    }

    func token(in config: Config) -> String? {
        config.text(tokenKeys, isSecret: true)?.value
    }

    /// The URL given on the command line, else the configured one, else the public service's.
    func apiURL(_ given: String?, in config: Config) -> Result<URL, RunnersError> {
        if let given { return Settings.url(given) }
        switch self {
            case .github:
                return config.text([.gitHubAPIURL]).map(Self.apiURL)
                    ?? .success(GitHubService.defaultBaseURL)
            case .gitlab:
                return config.text([.gitLabCIAPIURL, .gitLabHost]).map(Self.apiURL)
                    ?? .success(GitLabService.defaultBaseURL)
        }
    }

    /// A configured API URL. `gitlab.host` takes a host or a URL, as `glab` does.
    static func apiURL(_ setting: (key: SettingKey, value: String)) -> Result<URL, RunnersError> {
        let url =
            setting.key == .gitLabHost
            ? GitLabService.apiURL(forHost: setting.value)
            : Settings.url(setting.value).map(Optional.some).getOrElse(nil)
        return .fromOptional(url, error: setting.key.invalid(setting.value, expected: "a URL"))
    }

    /// The token to use when none is configured.
    func fallbackToken(apiURL: URL) async -> Result<String, RunnersError> {
        switch self {
            case .github:
                await GHCLI.token(hostname: GHCLI.hostname(forAPI: apiURL))
            case .gitlab:
                .failure(
                    .tokenUnavailable(
                        "set GITLAB_TOKEN to a personal access token with the read_api scope"
                    )
                )
        }
    }

    func service(token: String, apiURL: URL) -> any CIService {
        switch self {
            case .github: GitHubService(token: token, baseURL: apiURL)
            case .gitlab: GitLabService(token: token, baseURL: apiURL)
        }
    }
}
