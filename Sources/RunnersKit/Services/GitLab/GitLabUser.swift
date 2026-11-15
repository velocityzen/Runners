/// `GET /user`, `GET /users?username=`, and the `user` of pipelines and jobs.
struct GitLabUser: Codable, Sendable, Hashable {
    let id: Int
    let username: String

    var owner: Owner {
        Owner(id: String(id), login: username, kind: .user)
    }
}

/// `GET /groups/{id}`
struct GitLabGroup: Codable, Sendable, Hashable {
    let id: Int
    let fullPath: String

    enum CodingKeys: String, CodingKey {
        case id
        case fullPath = "full_path"
    }

    var owner: Owner {
        Owner(id: String(id), login: fullPath, kind: .organization)
    }
}
