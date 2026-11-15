/// `GET /user`, `GET /users/{login}`, and the `owner`/`actor` of other objects.
struct GitHubAccount: Codable, Sendable, Hashable {
    let id: Int
    let login: String
    /// `User`, `Organization` or `Bot`.
    let type: String

    var owner: Owner {
        Owner(id: String(id), login: login, kind: kind)
    }

    var kind: Owner.Kind {
        switch type {
            case "User": .user
            case "Organization": .organization
            case "Bot": .bot
            default: .unknown
        }
    }
}
