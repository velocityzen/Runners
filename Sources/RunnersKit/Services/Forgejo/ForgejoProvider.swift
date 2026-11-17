import Foundation

/// Forgejo Actions on Codeberg or another Forgejo instance. Without a token it reads public
/// repositories only.
public struct ForgejoProvider: Provider {
    public let id = "forgejo"
    public let name = "Forgejo Actions"
    public let tokenSettings: [ProviderSetting] = [
        .setting("forgejo.token"), .environment("codeberg.token"),
    ]
    public let apiURLSettings: [ProviderSetting] = [.setting("forgejo.host")]

    public init() {}

    public var repositoryTerm: (singular: String, plural: String) {
        ("repository", "repositories")
    }

    public func fallbackAPIURL() async -> Result<URL, RunnersError> {
        .success(ForgejoService.defaultBaseURL)
    }

    /// `forgejo.host` takes a host or a URL.
    public func apiURL(_ value: String, from setting: ProviderSetting) -> URL? {
        ForgejoService.apiURL(forHost: value)
    }

    public func apiURLFormat(of setting: ProviderSetting) -> String {
        "a host or a URL"
    }

    /// No token: public repositories only, read anonymously.
    public func fallbackToken(apiURL: URL) async -> Result<String, RunnersError> {
        .success("")
    }

    public func service(token: String, apiURL: URL, transport: any HTTPTransport) -> any CIService {
        ForgejoService(token: token, baseURL: apiURL, transport: transport)
    }
}
