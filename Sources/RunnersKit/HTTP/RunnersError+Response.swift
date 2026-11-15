import FP
import Foundation

extension RunnersError {
    /// The error an HTTP status means for REST APIs that report quotas in `X-RateLimit-*` or
    /// `RateLimit-*` headers and throttle with 429 and `Retry-After`.
    public init(response: HTTPResponse, url: URL) {
        let message = APIErrorBody.message(in: response.body)
        switch response.status {
            case 401: self = .unauthorized(message)
            case 403 where response.isQuotaSpent:
                self = .rateLimited(resetAt: response.rateLimitReset)
            case 403: self = .forbidden(message)
            case 404: self = .notFound(url.path())
            case 429 where response.isQuotaSpent && response.retryAfter == nil:
                self = .rateLimited(resetAt: response.rateLimitReset)
            case 429: self = .throttled(retryAfter: response.retryAfter)
            case 500...: self = .server(status: response.status, message: message)
            default: self = .unexpectedStatus(response.status, message: message)
        }
    }
}

extension HTTPResponse {
    var isQuotaSpent: Bool {
        (header("x-ratelimit-remaining") ?? header("ratelimit-remaining")) == "0"
    }

    var rateLimitReset: Date? {
        (header("x-ratelimit-reset") ?? header("ratelimit-reset"))
            .flatMap(TimeInterval.init)
            .map(Date.init(timeIntervalSince1970:))
    }

    var retryAfter: Duration? {
        header("retry-after")
            .flatMap(Int64.init)
            .map(Duration.seconds)
    }
}

/// The JSON body sent with an error status: `{"message": "…"}`, or `{"error": "…"}` on GitLab.
struct APIErrorBody: Decodable {
    let message: String?
    let error: String?

    static func message(in body: Data) -> String {
        JSONCoding.decode(APIErrorBody.self, from: body)
            .map { $0.message ?? $0.error }
            .getOrElse(nil)
            ?? String(decoding: body.prefix(200), as: UTF8.self)
    }
}
