import FP
import Foundation

/// The Woodpecker REST endpoints the service reads, answering in Woodpecker's own shapes.
struct WoodpeckerAPI: Sendable {
    /// The most a page of pipelines holds.
    static let pageSize = 50

    let client: APIClient
    /// The server's web UI, for links to pipelines.
    let server: URL

    /// A Bearer token; an empty token sends none.
    static func headers(token: String) -> [String: String] {
        var headers = ["Accept": "application/json", "User-Agent": "Runners"]
        if !token.isEmpty { headers["Authorization"] = "Bearer \(token)" }
        return headers
    }

    /// A rejected token is most often the forge's, which Woodpecker doesn't take.
    static func classify(server: URL) -> @Sendable (HTTPResponse, URL) -> RunnersError {
        { response, url in
            let error = RunnersError(response: response, url: url)
            guard case .unauthorized(let message) = error else { return error }
            let host = server.host() ?? server.absoluteString
            return .unauthorized(
                "\(message); WOODPECKER_TOKEN takes a personal access token from your user "
                    + "page on \(host), not a Codeberg or forge token"
            )
        }
    }

    /// The user the token belongs to.
    func authenticatedUser() async -> Result<WoodpeckerUser, RunnersError> {
        await client.value(["user"])
    }

    /// Every active repository the user can reach, from all owners, in one list.
    func repositories() async -> Result<[WoodpeckerRepository], RunnersError> {
        await client.value(["user", "repos"])
    }

    /// A repository by `owner/name`. Public ones need no token.
    func repository(_ fullName: String) async -> Result<WoodpeckerRepository, RunnersError> {
        await client.value(["repos", "lookup"] + fullName.split(separator: "/").map(String.init))
    }

    /// The pipelines with one status, newest first. Woodpecker filters by one status per
    /// request and pages with no total, so this reads pages until one comes back short.
    func pipelines(
        of repositoryID: String,
        status: String
    ) async -> Result<[WoodpeckerPipeline], RunnersError> {
        await page(1, of: repositoryID, status: status, [])
    }

    func page(
        _ number: Int,
        of repositoryID: String,
        status: String,
        _ found: [WoodpeckerPipeline]
    ) async -> Result<[WoodpeckerPipeline], RunnersError> {
        await client.value(
            ["repos", repositoryID, "pipelines"],
            [
                URLQueryItem(name: "status", value: status),
                URLQueryItem(name: "page", value: String(number)),
                URLQueryItem(name: "perPage", value: String(Self.pageSize)),
            ],
            as: [WoodpeckerPipeline].self
        )
        .flatMapAsync { page in
            guard page.count == Self.pageSize else { return .success(found + page) }
            return await self.page(number + 1, of: repositoryID, status: status, found + page)
        }
    }

    /// One pipeline, with its workflows and their steps.
    func pipeline(
        _ number: String,
        of repositoryID: String
    ) async -> Result<WoodpeckerPipeline, RunnersError> {
        await client.value(["repos", repositoryID, "pipelines", number])
    }
}
