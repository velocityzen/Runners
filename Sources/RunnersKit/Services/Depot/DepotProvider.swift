import Foundation

/// GitHub Actions jobs on Depot's runners, as Depot reports them. The same organization API
/// token and API URL as Depot CI's.
public struct DepotProvider: Provider {
    public let id = "depot"
    public let name = "Depot"
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
        await DepotCIProvider().fallbackToken(apiURL: apiURL)
    }

    public func service(token: String, apiURL: URL, transport: any HTTPTransport) -> any CIService {
        DepotService(token: token, baseURL: apiURL, transport: transport)
    }
}
