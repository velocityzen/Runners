import FP
import Foundation

extension GitHubError {
    /// Passes a 2xx response through and turns any other into the matching error.
    static func check(_ response: HTTPResponse, for url: URL) -> Result<HTTPResponse, GitHubError> {
        response.isSuccess ? .success(response) : .failure(GitHubError(response, url: url))
    }

    init(_ response: HTTPResponse, url: URL) {
        let message = APIErrorBody.message(in: response.body)
        switch response.status {
            case 401: self = .unauthorized(message)
            case 403, 429: self = .limitOrForbidden(response, message: message)
            case 404: self = .notFound(url.path())
            case 500...: self = .server(status: response.status, message: message)
            default: self = .unexpectedStatus(response.status, message: message)
        }
    }

    /// GitHub answers both rate limits and missing permissions with 403.
    static func limitOrForbidden(_ response: HTTPResponse, message: String) -> GitHubError {
        if let seconds = response.header("retry-after").flatMap(Int64.init) {
            return .secondaryRateLimited(retryAfter: .seconds(seconds))
        }
        if response.header("x-ratelimit-remaining") == "0" {
            return .rateLimited(resetAt: response.rateLimitReset)
        }
        if response.status == 429 || message.localizedStandardContains("secondary rate limit") {
            return .secondaryRateLimited(retryAfter: nil)
        }
        return .forbidden(message)
    }
}

/// The JSON body GitHub sends with an error status.
struct APIErrorBody: Decodable {
    let message: String

    static func message(in body: Data) -> String {
        Result { try JSONDecoder().decode(APIErrorBody.self, from: body) }
            .map(\.message)
            .getOrElse(String(decoding: body.prefix(200), as: UTF8.self))
    }
}
