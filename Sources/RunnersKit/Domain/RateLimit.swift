import Foundation

/// How much of the API quota is left.
public struct RateLimit: Codable, Sendable, Hashable {
    public let limit: Int
    public let remaining: Int
    public let resetAt: Date

    public init(limit: Int, remaining: Int, resetAt: Date) {
        self.limit = limit
        self.remaining = remaining
        self.resetAt = resetAt
    }

    enum CodingKeys: String, CodingKey {
        case limit, remaining
        case resetAt = "reset_at"
    }
}
