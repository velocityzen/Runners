import Foundation

/// WarpBuild's runner instances, grouped by runner set. The key is a WarpBuild API key with
/// the CI scope.
public struct WarpBuildProvider: Provider {
    public let id = "warpbuild"
    public let name = "WarpBuild"
    /// `WARPBUILD_API_KEY`
    public let tokenSettings: [ProviderSetting] = [.setting("warpbuild.api_key")]
    /// `WARPBUILD_API_URL`
    public let apiURLSettings: [ProviderSetting] = [.setting("warpbuild.api_url")]

    public init() {}

    public var repositoryTerm: (singular: String, plural: String) {
        ("runner set", "runner sets")
    }

    /// A runner set's ID, name or label: anything but blank.
    public func isRepositoryName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var repositoryNameFormat: String {
        "a WarpBuild runner set's ID, name or label"
    }

    public func fallbackAPIURL() async -> Result<URL, RunnersError> {
        .success(WarpBuildService.defaultBaseURL)
    }

    public func fallbackToken(apiURL: URL) async -> Result<String, RunnersError> {
        .failure(
            .tokenUnavailable(
                "set WARPBUILD_API_KEY to an API key with the CI scope, from API Keys in the "
                    + "WarpBuild dashboard"
            )
        )
    }

    public func service(token: String, apiURL: URL, transport: any HTTPTransport) -> any CIService {
        WarpBuildService(key: token, baseURL: apiURL, transport: transport)
    }
}
