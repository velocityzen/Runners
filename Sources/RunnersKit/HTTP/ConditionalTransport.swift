import Foundation
import Synchronization

/// Sends `If-None-Match` for URLs it has seen and answers `304 Not Modified` from its cache.
///
/// GitHub does not count 304 responses against the rate limit, so repeated refreshes only pay
/// for what changed. Servers that send no `ETag` are passed through untouched, and so are
/// requests other than GET: a POST's answer depends on its body, not just its URL. Share an
/// ``ETagCache`` saved to disk to carry that across runs.
public struct ConditionalTransport<Base: HTTPTransport>: HTTPTransport {
    let base: Base
    let cache: ETagCache

    public init(_ base: Base, cache: ETagCache = ETagCache()) {
        self.base = base
        self.cache = cache
    }

    public func send(_ request: HTTPRequest) async -> Result<HTTPResponse, RunnersError> {
        guard request.isGet else { return await base.send(request) }
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
