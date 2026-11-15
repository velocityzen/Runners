import FPRetry
import Foundation

/// GitLab CI: pipelines and their jobs, from the REST API (v4). Works with gitlab.com and
/// self-managed instances.
public struct GitLabService: CIService {
    let api: GitLabAPI

    public var provider: any Provider { GitLabProvider() }

    public init(
        token: String,
        baseURL: URL = GitLabService.defaultBaseURL,
        transport: any HTTPTransport = ConditionalTransport(URLSessionTransport()),
        retryPolicy: RetryPolicy = APIClient.defaultRetryPolicy
    ) {
        api = GitLabAPI(
            client: APIClient(
                baseURL: baseURL,
                headers: GitLabAPI.headers(token: token),
                transport: transport,
                retryPolicy: retryPolicy
            )
        )
    }

    /// `https://gitlab.com/api/v4`
    public static var defaultBaseURL: URL {
        apiURL(forHost: "gitlab.com") ?? URL(filePath: "/")
    }

    /// The v4 API of a GitLab instance: `https://<host>/api/v4`. Takes a bare host or a URL.
    public static func apiURL(forHost host: String) -> URL? {
        let base = host.contains("://") ? host : "https://\(host)"
        return URL(string: base).map { $0.appending(path: "api/v4") }
    }

    /// GitLab reports its quota only in response headers, not through an endpoint.
    public func rateLimit() async -> RateLimit? {
        nil
    }
}
