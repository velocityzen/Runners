import Foundation

/// GitLab CI/CD on gitlab.com or a self-managed instance.
public struct GitLabProvider: Provider {
    public let id = "gitlab"
    public let name = "GitLab"
    public let tokenSettings: [ProviderSetting] = [
        .setting("gitlab.token"), .environment("gitlab.access_token"),
    ]
    /// `CI_API_V4_URL` first, as GitLab CI jobs set it.
    public let apiURLSettings: [ProviderSetting] = [
        .environment("ci.api_v4_url"), .setting("gitlab.host"),
    ]

    public init() {}

    public var repositoryTerm: (singular: String, plural: String) {
        ("project", "projects")
    }

    public func fallbackAPIURL() async -> Result<URL, RunnersError> {
        .success(GitLabService.defaultBaseURL)
    }

    /// `gitlab.host` takes a host or a URL, as `glab` does.
    public func apiURL(_ value: String, from setting: ProviderSetting) -> URL? {
        setting.name == "gitlab.host"
            ? GitLabService.apiURL(forHost: value)
            : URL(string: value).flatMap { $0.host() == nil ? nil : $0 }
    }

    public func fallbackToken(apiURL: URL) async -> Result<String, RunnersError> {
        .failure(
            .tokenUnavailable("set GITLAB_TOKEN to a personal access token with the read_api scope")
        )
    }

    public func service(token: String, apiURL: URL, transport: any HTTPTransport) -> any CIService {
        GitLabService(token: token, baseURL: apiURL, transport: transport)
    }
}
