import Foundation

/// Woodpecker CI on ci.codeberg.org or another Woodpecker server. Its token is a Woodpecker
/// personal access token, not the forge's.
public struct WoodpeckerProvider: Provider {
    public let id = "woodpecker"
    public let name = "Woodpecker CI"
    public let tokenSettings: [ProviderSetting] = [.setting("woodpecker.token")]
    /// `WOODPECKER_SERVER`, as woodpecker-cli reads it.
    public let apiURLSettings: [ProviderSetting] = [.setting("woodpecker.server")]

    public init() {}

    public var repositoryTerm: (singular: String, plural: String) {
        ("repository", "repositories")
    }

    public func fallbackAPIURL() async -> Result<URL, RunnersError> {
        .success(WoodpeckerService.defaultBaseURL)
    }

    /// `woodpecker.server` takes the server, as a host or a URL; the API is under `/api`.
    public func apiURL(_ value: String, from setting: ProviderSetting) -> URL? {
        WoodpeckerService.apiURL(forServer: value)
    }

    public func apiURLFormat(of setting: ProviderSetting) -> String {
        "a host or a URL"
    }

    /// No token: public repositories named with `--repo` only.
    public func fallbackToken(apiURL: URL) async -> Result<String, RunnersError> {
        .success("")
    }

    public func service(token: String, apiURL: URL, transport: any HTTPTransport) -> any CIService {
        WoodpeckerService(token: token, baseURL: apiURL, transport: transport)
    }
}
