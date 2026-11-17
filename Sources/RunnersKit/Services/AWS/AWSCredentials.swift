import FP
import Foundation

/// An AWS access key, with the session token that temporary keys come with.
public struct AWSCredentials: Codable, Sendable, Hashable, CustomStringConvertible {
    public let accessKeyID: String
    public let secretAccessKey: String
    public let sessionToken: String?

    public init(accessKeyID: String, secretAccessKey: String, sessionToken: String? = nil) {
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
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

    /// The credentials in `credential_process` JSON, which may carry more, such as when they
    /// expire.
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
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessKeyID = try container.decode(String.self, forKey: .accessKeyID)
        secretAccessKey = try container.decode(String.self, forKey: .secretAccessKey)
        sessionToken = try container.decodeIfPresent(String.self, forKey: .sessionToken)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .version)
        try container.encode(accessKeyID, forKey: .accessKeyID)
        try container.encode(secretAccessKey, forKey: .secretAccessKey)
        try container.encodeIfPresent(sessionToken, forKey: .sessionToken)
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
