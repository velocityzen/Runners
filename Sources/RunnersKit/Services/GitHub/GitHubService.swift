import FP
import FPRetry
import Foundation

/// GitHub Actions: workflow runs and their jobs, from the REST API.
public struct GitHubService: CIService {
    let api: GitHubAPI

    public var provider: Provider { .github }

    public init(
        token: String,
        baseURL: URL = GitHubService.defaultBaseURL,
        transport: any HTTPTransport = ConditionalTransport(URLSessionTransport()),
        retryPolicy: RetryPolicy = APIClient.defaultRetryPolicy
    ) {
        api = GitHubAPI(
            client: APIClient(
                baseURL: baseURL,
                headers: GitHubAPI.headers(token: token),
                transport: transport,
                retryPolicy: retryPolicy,
                classify: GitHubAPI.classify
            )
        )
    }

    /// `https://api.github.com`
    public static var defaultBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        return components.url ?? URL(filePath: "/")
    }

    /// Asking for the quota does not use it up. A server without one (GitHub Enterprise with
    /// limits off) is no reason to fail.
    public func rateLimit() async -> RateLimit? {
        await api.rateLimit()
            .map { Optional.some($0.rateLimit) }
            .getOrElse(nil)
    }
}
