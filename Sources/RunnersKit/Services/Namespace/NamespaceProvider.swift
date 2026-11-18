import Foundation

/// GitHub Actions jobs on Namespace's runners. The token is a Namespace tenant token; without
/// one, the signed-in `nsc` CLI gives a development token.
public struct NamespaceProvider: Provider {
    public let id = "namespace"
    public let name = "Namespace"
    /// `NAMESPACE_TOKEN`, or `NSC_TOKEN`.
    public let tokenSettings: [ProviderSetting] = [
        .setting("namespace.token"), .environment("nsc.token"),
    ]
    /// `NAMESPACE_API_URL`, or `NSC_GLOBAL_ENDPOINT` as the nsc CLI reads it.
    public let apiURLSettings: [ProviderSetting] = [
        .setting("namespace.api_url"), .environment("nsc.global_endpoint"),
    ]

    /// `nsc auth generate-dev-token`, which prints a short-lived token once `nsc login` has run.
    static let devToken = CLIToken(
        "nsc",
        ["auth", "generate-dev-token"],
        hint: "set NSC_TOKEN to a token from `nsc token create` that grants list and get on "
            + "github/runner-profile and instance, or run `nsc login`"
    )

    public init() {}

    public var repositoryTerm: (singular: String, plural: String) {
        ("repository", "repositories")
    }

    public func fallbackAPIURL() async -> Result<URL, RunnersError> {
        .success(NamespaceService.defaultBaseURL)
    }

    public func fallbackToken(apiURL: URL) async -> Result<String, RunnersError> {
        await Self.devToken.token()
    }

    public func service(token: String, apiURL: URL, transport: any HTTPTransport) -> any CIService {
        NamespaceService(token: token, baseURL: apiURL, transport: transport)
    }
}
