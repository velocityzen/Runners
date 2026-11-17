import FPRetry
import Foundation

/// Forgejo Actions: workflow runs and their jobs, from Forgejo's REST API (v1). Works with
/// Codeberg and other Forgejo instances.
public struct ForgejoService: CIService {
    let api: ForgejoAPI
    /// Whether requests go without a token, which sees public repositories only.
    let isAnonymous: Bool

    public var provider: any Provider { ForgejoProvider() }

    /// - Parameter token: a personal access token, or empty to read public repositories
    ///   without one.
    public init(
        token: String,
        baseURL: URL = ForgejoService.defaultBaseURL,
        transport: any HTTPTransport = ConditionalTransport(URLSessionTransport()),
        retryPolicy: RetryPolicy = APIClient.defaultRetryPolicy
    ) {
        api = ForgejoAPI(
            client: APIClient(
                baseURL: baseURL,
                headers: ForgejoAPI.headers(token: token),
                transport: transport,
                retryPolicy: retryPolicy
            )
        )
        isAnonymous = token.isEmpty
    }

    /// `https://codeberg.org/api/v1`
    public static var defaultBaseURL: URL {
        apiURL(forHost: "codeberg.org") ?? URL(filePath: "/")
    }

    /// The v1 API of a Forgejo instance: `https://<host>/api/v1`. Takes a bare host, a URL, or
    /// the API URL itself.
    public static func apiURL(forHost host: String) -> URL? {
        let base = host.contains("://") ? host : "https://\(host)"
        guard let url = URL(string: base), url.host() != nil else { return nil }
        return url.path().hasSuffix("/api/v1") || url.path().hasSuffix("/api/v1/")
            ? url : url.appending(path: "api/v1")
    }

    /// Forgejo has no quota endpoint.
    public func rateLimit() async -> RateLimit? {
        nil
    }
}
