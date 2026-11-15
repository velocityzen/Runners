import Foundation

/// GitHub Actions on github.com or GitHub Enterprise. A signed-in `gh` supplies the token when
/// none is set.
public struct GitHubProvider: Provider {
    public let id = "github"
    public let name = "GitHub"
    /// `GH_TOKEN` first, as `gh` does.
    public let tokenSettings: [ProviderSetting] = [
        .environment("gh.token"), .setting("github.token"),
    ]
    public let apiURLSettings: [ProviderSetting] = [.setting("github.api_url")]

    public init() {}

    public var repositoryTerm: (singular: String, plural: String) {
        ("repository", "repositories")
    }

    public var defaultAPIURL: URL {
        GitHubService.defaultBaseURL
    }

    public func fallbackToken(apiURL: URL) async -> Result<String, RunnersError> {
        await GHCLI.token(hostname: GHCLI.hostname(forAPI: apiURL))
    }

    public func service(token: String, apiURL: URL, transport: any HTTPTransport) -> any CIService {
        GitHubService(token: token, baseURL: apiURL, transport: transport)
    }
}
