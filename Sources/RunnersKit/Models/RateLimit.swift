import Foundation

/// The core REST API quota of the token.
public struct RateLimit: Codable, Sendable, Hashable {
    public let limit: Int
    public let remaining: Int
    public let used: Int
    /// When the quota resets, in seconds since 1970.
    public let reset: Int

    public init(limit: Int, remaining: Int, used: Int, reset: Int) {
        self.limit = limit
        self.remaining = remaining
        self.used = used
        self.reset = reset
    }

    public var resetAt: Date {
        Date(timeIntervalSince1970: TimeInterval(reset))
    }
}

/// `GET /rate_limit`
struct RateLimitResponse: Decodable {
    struct Resources: Decodable {
        let core: RateLimit
    }

    let resources: Resources
}
