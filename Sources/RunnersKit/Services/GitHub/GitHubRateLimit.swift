import Foundation

/// The core REST quota, from `GET /rate_limit`.
struct GitHubRateLimit: Codable, Sendable, Hashable {
    let limit: Int
    let remaining: Int
    /// Seconds since 1970.
    let reset: Int

    var rateLimit: RateLimit {
        RateLimit(
            limit: limit,
            remaining: remaining,
            resetAt: Date(timeIntervalSince1970: TimeInterval(reset))
        )
    }
}

struct GitHubRateLimitResponse: Codable {
    struct Resources: Codable {
        let core: GitHubRateLimit
    }

    let resources: Resources
}
