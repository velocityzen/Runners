import FPRetry
import Foundation

/// Woodpecker CI: pipelines and their workflows, from the server's REST API.
public struct WoodpeckerService: CIService {
    let api: WoodpeckerAPI
    /// Whether requests go without a token, which sees public repositories only.
    let isAnonymous: Bool

    public var provider: any Provider { WoodpeckerProvider() }

    /// - Parameters:
    ///   - token: a Woodpecker personal access token, or empty to read public repositories
    ///     without one.
    ///   - baseURL: the server's API, such as `https://ci.codeberg.org/api`.
    public init(
        token: String,
        baseURL: URL = WoodpeckerService.defaultBaseURL,
        transport: any HTTPTransport = ConditionalTransport(URLSessionTransport()),
        retryPolicy: RetryPolicy = APIClient.defaultRetryPolicy
    ) {
        api = WoodpeckerAPI(
            client: APIClient(
                baseURL: baseURL,
                headers: WoodpeckerAPI.headers(token: token),
                transport: transport,
                retryPolicy: retryPolicy,
                classify: WoodpeckerAPI.classify(server: baseURL.deletingLastPathComponent())
            ),
            server: baseURL.deletingLastPathComponent()
        )
        isAnonymous = token.isEmpty
    }

    /// `https://ci.codeberg.org/api`
    public static var defaultBaseURL: URL {
        apiURL(forServer: "ci.codeberg.org") ?? URL(filePath: "/")
    }

    /// A server's API: `https://<host>/api`. Takes a bare host, the server's URL, or the API
    /// URL itself.
    public static func apiURL(forServer server: String) -> URL? {
        let base = server.contains("://") ? server : "https://\(server)"
        guard let url = URL(string: base), url.host() != nil else { return nil }
        return url.lastPathComponent == "api" ? url : url.appending(path: "api")
    }

    /// Woodpecker has no quota endpoint.
    public func rateLimit() async -> RateLimit? {
        nil
    }
}
