/// A GitHub user or organization.
public struct Account: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case user = "User"
        case organization = "Organization"
        case bot = "Bot"
        case unknown

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    public let id: Int
    public let login: String
    public let kind: Kind

    public init(id: Int, login: String, kind: Kind) {
        self.id = id
        self.login = login
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey {
        case id, login
        case kind = "type"
    }

    /// Logins are case-insensitive.
    public func isSameAccount(as other: Account) -> Bool {
        login.lowercased() == other.login.lowercased()
    }
}
