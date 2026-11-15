import Foundation
import Testing

@testable import RunnersKit

@Suite("Error classification")
struct RunnersErrorTests {
    let url = Fixtures.url("https://api.example.com/users/ghost")

    func error(_ response: HTTPResponse) -> RunnersError {
        RunnersError(response: response, url: url)
    }

    @Test("reads the message from GitHub's and GitLab's error bodies")
    func messages() {
        #expect(
            error(.raw(401, #"{"message":"Bad credentials"}"#)) == .unauthorized("Bad credentials")
        )
        #expect(error(.raw(401, #"{"error":"invalid_token"}"#)) == .unauthorized("invalid_token"))
        #expect(error(.raw(401, "nope")) == .unauthorized("nope"))
    }

    @Test("names the path on 404")
    func notFound() {
        #expect(error(.notFound) == .notFound("/users/ghost"))
    }

    @Test("tells a spent quota from a missing permission, in either header style")
    func forbidden() {
        let github = error(
            .raw(
                403,
                "{}",
                headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000000"]
            )
        )
        #expect(github == .rateLimited(resetAt: Date(timeIntervalSince1970: 1_800_000_000)))
        #expect(!github.isTransient)

        let gitlab = error(
            .raw(429, "{}", headers: ["RateLimit-Remaining": "0", "RateLimit-Reset": "1800000000"])
        )
        #expect(gitlab == .rateLimited(resetAt: Date(timeIntervalSince1970: 1_800_000_000)))

        #expect(
            error(.raw(403, #"{"message":"Resource not accessible"}"#))
                == .forbidden("Resource not accessible")
        )
    }

    @Test("retries throttling after the wait the server asks for, or a minute")
    func throttled() {
        let asked = error(.raw(429, "{}", headers: ["Retry-After": "7"]))
        #expect(asked == .throttled(retryAfter: .seconds(7)))
        #expect(asked.isTransient)
        #expect(asked.retryAfter == .seconds(7))
        #expect(error(.raw(429)).retryAfter == .seconds(60))
    }

    @Test("retries server errors only")
    func transient() {
        #expect(error(.raw(502, "Bad Gateway")).isTransient)
        #expect(
            error(.raw(422, #"{"message":"Validation Failed"}"#))
                == .unexpectedStatus(422, message: "Validation Failed")
        )
        #expect(!error(.raw(422)).isTransient)
    }

    @Test("treats GitHub's 403 secondary rate limit as throttling")
    func gitHubSecondaryLimit() {
        let withWait = GitHubAPI.classify(.raw(403, "{}", headers: ["Retry-After": "30"]), url: url)
        #expect(withWait == .throttled(retryAfter: .seconds(30)))

        let withMessage = GitHubAPI.classify(
            .raw(403, #"{"message":"You have exceeded a secondary rate limit."}"#),
            url: url
        )
        #expect(withMessage == .throttled(retryAfter: nil))
        #expect(
            GitHubAPI.classify(.raw(403, #"{"message":"Nope"}"#), url: url) == .forbidden("Nope")
        )
    }
}
