import FP
import FPRetry
import Foundation

/// Reads a JSON REST API: authenticated, paginated by `Link` headers, retried on transient
/// failures. Each service configures one with its base URL, headers and error rules.
public struct APIClient: Sendable {
    public let baseURL: URL
    let headers: [String: String]
    let transport: any HTTPTransport
    let retryPolicy: RetryPolicy
    let classify: @Sendable (HTTPResponse, URL) -> RunnersError

    public init(
        baseURL: URL,
        headers: [String: String],
        transport: any HTTPTransport = ConditionalTransport(URLSessionTransport()),
        retryPolicy: RetryPolicy = APIClient.defaultRetryPolicy,
        classify: @escaping @Sendable (HTTPResponse, URL) -> RunnersError = RunnersError.init(
            response:
            url:
        )
    ) {
        self.baseURL = baseURL
        self.headers = headers
        self.transport = transport
        self.retryPolicy = retryPolicy
        self.classify = classify
    }

    /// Up to 3 retries with growing waits, longer when the server asks for it, giving up on waits
    /// over 90 seconds.
    public static var defaultRetryPolicy: RetryPolicy {
        RetryPolicy.exponentialBackoff(.milliseconds(500))
            .and(.limitRetries(3))
            .capDelay(.seconds(8))
            .jitter(0.5...1)
            .and(.requestedDelay)
            .limitRetriesByDelay(.seconds(90))
    }

    // MARK: - Requests

    /// The URL of a path below the base URL. Each segment is one path component: a `/` inside
    /// it is escaped, as GitLab wants for `group/project` IDs.
    func url(_ segments: [String], _ query: [URLQueryItem] = []) -> URL {
        var components =
            URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        let base =
            components.percentEncodedPath.hasSuffix("/")
            ? String(components.percentEncodedPath.dropLast())
            : components.percentEncodedPath
        components.percentEncodedPath = ([base] + segments.map(Self.escape)).joined(separator: "/")
        components.queryItems = query.isEmpty ? nil : query
        return components.url ?? baseURL
    }

    static func escape(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .pathSegmentAllowed) ?? segment
    }

    func response(for url: URL) async -> Result<HTTPResponse, RunnersError> {
        await withRetry(retryPolicy, while: \.isTransient, requestedDelay: \.retryAfter) {
            await transport.send(HTTPRequest(url: url, headers: headers))
                .flatMap(check(url))
        }
    }

    /// Passes a 2xx response through and turns any other into the matching error.
    func check(_ url: URL) -> (HTTPResponse) -> Result<HTTPResponse, RunnersError> {
        { response in response.isSuccess ? .success(response) : .failure(classify(response, url)) }
    }

    /// One object.
    func value<T: Decodable>(
        _ segments: [String],
        _ query: [URLQueryItem] = [],
        as type: T.Type = T.self
    ) async -> Result<T, RunnersError> {
        await response(for: url(segments, query))
            .flatMap { JSONCoding.decode(type, from: $0.body) }
    }

    /// Every item of a list, following `Link: rel="next"` page by page.
    func all<P: PagedResponse>(
        _ segments: [String],
        _ query: [URLQueryItem],
        as type: P.Type
    ) async -> Result<[P.Item], RunnersError> {
        await collect(from: url(segments, query), as: type)
    }

    private func collect<P: PagedResponse>(
        from url: URL,
        as type: P.Type
    ) async -> Result<[P.Item], RunnersError> {
        await response(for: url)
            .flatMap { Page.decode(type, from: $0) }
            .flatMapAsync { page in await remaining(after: page, as: type) }
    }

    private func remaining<P: PagedResponse>(
        after page: Page<P.Item>,
        as type: P.Type
    ) async -> Result<[P.Item], RunnersError> {
        guard let next = page.next else { return .success(page.items) }
        return await collect(from: next, as: type)
            .map { page.items + $0 }
    }
}

extension CharacterSet {
    /// What may stand unescaped in one path component.
    static let pathSegmentAllowed = CharacterSet.urlPathAllowed.subtracting(
        CharacterSet(charactersIn: "/")
    )
}

extension URLQueryItem {
    static let perPage = URLQueryItem(name: "per_page", value: "100")
}
