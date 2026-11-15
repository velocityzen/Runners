import FP
import FPRetry
import Foundation

/// Reads the GitHub REST API: authenticated, paginated, retried on transient failures.
public struct GitHubClient: Sendable {
    public let baseURL: URL
    let token: String
    let transport: any HTTPTransport
    let retryPolicy: RetryPolicy

    public init(
        token: String,
        baseURL: URL = GitHubClient.defaultBaseURL,
        transport: any HTTPTransport = ConditionalTransport(URLSessionTransport()),
        retryPolicy: RetryPolicy = GitHubClient.defaultRetryPolicy
    ) {
        self.token = token
        self.baseURL = baseURL
        self.transport = transport
        self.retryPolicy = retryPolicy
    }

    /// `https://api.github.com`
    public static var defaultBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        return components.url ?? URL(filePath: "/")
    }

    /// Up to 3 retries with growing waits, longer when GitHub asks for it, giving up on waits
    /// over 90 seconds.
    public static var defaultRetryPolicy: RetryPolicy {
        RetryPolicy.exponentialBackoff(.milliseconds(500))
            .and(.limitRetries(3))
            .capDelay(.seconds(8))
            .jitter(0.5...1)
            .and(.requestedDelay)
            .limitRetriesByDelay(.seconds(90))
    }

    /// The API version this client is written against.
    static let apiVersion = "2026-03-10"

    // MARK: - Requests

    func url(_ path: String, _ query: [URLQueryItem] = []) -> URL {
        baseURL.appending(path: path).appending(queryItems: query)
    }

    func request(for url: URL) -> HTTPRequest {
        HTTPRequest(
            url: url,
            headers: [
                "Accept": "application/vnd.github+json",
                "Authorization": "Bearer \(token)",
                "User-Agent": "Runners",
                "X-GitHub-Api-Version": Self.apiVersion,
            ]
        )
    }

    func response(for url: URL) async -> Result<HTTPResponse, GitHubError> {
        await withRetry(retryPolicy, while: \.isTransient, requestedDelay: \.retryAfter) {
            await transport.send(request(for: url))
                .flatMap { GitHubError.check($0, for: url) }
        }
    }

    /// One object.
    func value<T: Decodable>(
        _ path: String,
        _ query: [URLQueryItem] = [],
        as type: T.Type = T.self
    ) async -> Result<T, GitHubError> {
        await response(for: url(path, query))
            .flatMap { GitHubJSON.decode(T.self, from: $0.body) }
    }

    /// Every item of a list, following `Link: rel="next"` page by page.
    func all<P: PagedResponse>(
        _ path: String,
        _ query: [URLQueryItem],
        as type: P.Type
    ) async -> Result<[P.Item], GitHubError> {
        await collect(from: url(path, query), as: type)
    }

    private func collect<P: PagedResponse>(
        from url: URL,
        as type: P.Type
    ) async -> Result<[P.Item], GitHubError> {
        await response(for: url)
            .flatMap { Page.decode(type, from: $0) }
            .flatMapAsync { page in await remaining(after: page, as: type) }
    }

    private func remaining<P: PagedResponse>(
        after page: Page<P.Item>,
        as type: P.Type
    ) async -> Result<[P.Item], GitHubError> {
        guard let next = page.next else { return .success(page.items) }
        return await collect(from: next, as: type)
            .map { page.items + $0 }
    }
}
