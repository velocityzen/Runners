import FP
import Foundation

/// An AWS access key, with the session token that temporary keys come with, and when they
/// expire.
public struct AWSCredentials: Codable, Sendable, Hashable, CustomStringConvertible {
    public let accessKeyID: String
    public let secretAccessKey: String
    public let sessionToken: String?
    /// When temporary keys stop working; nil for keys that last.
    public let expiration: Date?

    public init(
        accessKeyID: String,
        secretAccessKey: String,
        sessionToken: String? = nil,
        expiration: Date? = nil
    ) {
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.expiration = expiration
    }

    /// Whether they stop working within `interval` of `now`: by then, or already.
    public func expire(within interval: TimeInterval, of now: Date) -> Bool {
        expiration.map { $0.timeIntervalSince(now) <= interval } ?? false
    }

    /// The key ID only: the secret and the session token stay out of logs.
    public var description: String {
        "AWSCredentials(\(accessKeyID))"
    }

    // MARK: - As a token

    /// The credentials as `credential_process` JSON, the form
    /// `aws configure export-credentials --format process` prints. ``AWSProvider`` passes them
    /// to its service as its token.
    public var token: String {
        (try? JSONEncoder.sorted.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// The credentials in `credential_process` JSON, ignoring what else it holds.
    public static func from(token: String) -> Result<AWSCredentials, RunnersError> {
        Result { try JSONDecoder().decode(AWSCredentials.self, from: Data(token.utf8)) }
            .mapError { _ in .tokenUnavailable(missingKeys) }
    }

    static let missingKeys = "AWS credentials need an access key ID and a secret"

    enum CodingKeys: String, CodingKey {
        case version = "Version"
        case accessKeyID = "AccessKeyId"
        case secretAccessKey = "SecretAccessKey"
        case sessionToken = "SessionToken"
        case expiration = "Expiration"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessKeyID = try container.decode(String.self, forKey: .accessKeyID)
        secretAccessKey = try container.decode(String.self, forKey: .secretAccessKey)
        sessionToken = try container.decodeIfPresent(String.self, forKey: .sessionToken)
        // ISO 8601, as Python writes it: `2026-11-17T19:34:20+00:00`, with a fraction at times.
        expiration = try container.decodeIfPresent(String.self, forKey: .expiration)
            .flatMap { try? Date.ISO8601FormatStyle.iso8601.parse($0) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .version)
        try container.encode(accessKeyID, forKey: .accessKeyID)
        try container.encode(secretAccessKey, forKey: .secretAccessKey)
        try container.encodeIfPresent(sessionToken, forKey: .sessionToken)
        try container.encodeIfPresent(expiration?.formatted(.iso8601), forKey: .expiration)
    }
}

extension JSONEncoder {
    /// Keys in order, so the same value always encodes the same.
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
