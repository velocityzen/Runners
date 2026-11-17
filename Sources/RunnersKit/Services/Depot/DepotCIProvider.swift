import Foundation

/// Depot CI: Depot's own workflow runner, not the GitHub Actions runners Depot also hosts. Its
/// token is a Depot organization API token.
public struct DepotCIProvider: Provider {
    public let id = "depot-ci"
    public let name = "Depot CI"
    /// `DEPOT_TOKEN`, as the depot CLI reads it.
    public let tokenSettings: [ProviderSetting] = [.setting("depot.token")]
    /// `DEPOT_API_URL`, as the depot CLI reads it.
    public let apiURLSettings: [ProviderSetting] = [.setting("depot.api_url")]

    public init() {}

    public var repositoryTerm: (singular: String, plural: String) {
        ("repository", "repositories")
    }

    public func fallbackAPIURL() async -> Result<URL, RunnersError> {
        .success(DepotCIService.defaultBaseURL)
    }

    public func fallbackToken(apiURL: URL) async -> Result<String, RunnersError> {
        .failure(
            .tokenUnavailable(
                "set DEPOT_TOKEN to an organization API token, from Settings → API Tokens in "
                    + "the Depot dashboard"
            )
        )
    }

    public func service(token: String, apiURL: URL, transport: any HTTPTransport) -> any CIService {
        DepotCIService(token: token, baseURL: apiURL, transport: transport)
    }
}
