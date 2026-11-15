import Foundation
import Testing

@testable import RunnersKit

@Suite("Error classification")
struct GitHubErrorTests {
    let url = Fixtures.url("https://api.github.com/users/ghost")

    func error(_ response: HTTPResponse) -> GitHubError {
        GitHubError(response, url: url)
    }

    @Test("passes 2xx responses through")
    func success() throws {
        let response = HTTPResponse.raw(200, "{}")
        #expect(try GitHubError.check(response, for: url).get() == response)
    }

    @Test("reads the message GitHub sends with 401")
    func unauthorized() {
        #expect(error(.raw(401, #"{"message":"Bad credentials"}"#)) == .unauthorized("Bad credentials"))
    }

    @Test("names the path on 404")
    func notFound() {
        #expect(error(.notFound) == .notFound("/users/ghost"))
    }

    @Test("tells a spent quota from a missing permission")
    func forbidden() {
        let spent = error(.raw(403, #"{"message":"API rate limit exceeded"}"#, headers: [
            "X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000000",
        ]))
        #expect(spent == .rateLimited(resetAt: Date(timeIntervalSince1970: 1_800_000_000)))
        #expect(!spent.isTransient)

        let denied = error(.raw(403, #"{"message":"Resource not accessible by integration"}"#))
        #expect(denied == .forbidden("Resource not accessible by integration"))
        #expect(!denied.isTransient)
    }

    @Test("retries the secondary limit after the wait GitHub asks for, or a minute")
    func secondary() {
        let asked = error(.raw(403, "{}", headers: ["Retry-After": "7"]))
        #expect(asked == .secondaryRateLimited(retryAfter: .seconds(7)))
        #expect(asked.isTransient)
        #expect(asked.retryAfter == .seconds(7))

        let unasked = error(.raw(429, #"{"message":"You have exceeded a secondary rate limit"}"#))
        #expect(unasked.retryAfter == .seconds(60))
    }

    @Test("retries server errors only")
    func transient() {
        #expect(error(.raw(502, "Bad Gateway")).isTransient)
        #expect(!error(.raw(422, #"{"message":"Validation Failed"}"#)).isTransient)
        #expect(error(.raw(422, #"{"message":"Validation Failed"}"#)) == .unexpectedStatus(422, message: "Validation Failed"))
    }
}
