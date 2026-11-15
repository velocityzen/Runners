import Foundation
import Synchronization

/// Sends `If-None-Match` for URLs it has seen and answers `304 Not Modified` from its cache.
///
/// GitHub does not count 304 responses against the rate limit, so repeated refreshes only pay
/// for what changed.
public struct ConditionalTransport<Base: HTTPTransport>: HTTPTransport {
    let base: Base
    let cache = ETagCache()

    public init(_ base: Base) {
        self.base = base
    }

    public func send(_ request: HTTPRequest) async -> Result<HTTPResponse, GitHubError> {
        let cached = cache[request.url]
        return await base.send(request.conditional(on: cached?.etag))
            .map { cache.resolve($0, for: request.url, cached: cached) }
    }
}

extension HTTPRequest {
    func conditional(on etag: String?) -> HTTPRequest {
        guard let etag else { return self }
        var request = self
        request.headers["If-None-Match"] = etag
        return request
    }
}

/// Responses by URL, with the ETag GitHub sent for each.
final class ETagCache: Sendable {
    struct Entry: Sendable {
        let etag: String
        let response: HTTPResponse
    }

    /// Enough for every repository and run of a large organization; cleared when exceeded.
    static let capacity = 4_096

    private let entries = Mutex<[URL: Entry]>([:])

    subscript(url: URL) -> Entry? {
        entries.withLock { $0[url] }
    }

    /// Swaps a 304 for the cached response, and caches a fresh response that has an ETag.
    func resolve(_ response: HTTPResponse, for url: URL, cached: Entry?) -> HTTPResponse {
        if response.status == 304, let cached {
            return cached.response.refreshed(with: response.headers)
        }
        if response.isSuccess, let etag = response.header("etag") {
            store(Entry(etag: etag, response: response), for: url)
        }
        return response
    }

    private func store(_ entry: Entry, for url: URL) {
        entries.withLock { entries in
            if entries.count >= Self.capacity { entries.removeAll() }
            entries[url] = entry
        }
    }
}

extension HTTPResponse {
    /// The cached body with the headers of the 304 that confirmed it.
    func refreshed(with newHeaders: [String: String]) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: headers.merging(newHeaders) { _, new in new },
            body: body
        )
    }
}
