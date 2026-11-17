import FP
import Foundation

/// The Forgejo REST endpoints the service reads, answering in Forgejo's own shapes.
struct ForgejoAPI: Sendable {
    /// The most a page holds by default.
    static let pageSize = 50

    let client: APIClient

    /// Forgejo takes `token …`; an empty token sends none.
    static func headers(token: String) -> [String: String] {
        var headers = ["Accept": "application/json", "User-Agent": "Runners"]
        if !token.isEmpty { headers["Authorization"] = "token \(token)" }
        return headers
    }

    /// The user the token belongs to.
    func authenticatedUser() async -> Result<ForgejoAccount, RunnersError> {
        await client.value(["user"])
    }

    func organization(_ name: String) async -> Result<ForgejoOrganization, RunnersError> {
        await client.value(["orgs", name])
    }

    func user(_ name: String) async -> Result<ForgejoAccount, RunnersError> {
        await client.value(["users", name])
    }

    /// A repository by `owner/name`.
    func repository(_ fullName: String) async -> Result<ForgejoRepository, RunnersError> {
        await client.value(Self.repositoryPath(fullName))
    }

    /// Repository lists page with `Link`, like GitHub's.
    func repositories(_ path: [String]) async -> Result<[ForgejoRepository], RunnersError> {
        await client.all(path, [Self.limit], as: [ForgejoRepository].self)
    }

    /// The runs with any of these statuses. The list says how many there are in its body,
    /// not in a `Link` header, so this pages until it has them all.
    func runs(
        in fullName: String,
        statuses: [String]
    ) async -> Result<[ForgejoRun], RunnersError> {
        let query = statuses.map { URLQueryItem(name: "status", value: $0) } + [Self.limit]
        return await page(1, of: Self.repositoryPath(fullName) + ["actions", "runs"], query, [])
    }

    func page(
        _ number: Int,
        of path: [String],
        _ query: [URLQueryItem],
        _ found: [ForgejoRun]
    ) async -> Result<[ForgejoRun], RunnersError> {
        await client.value(
            path,
            query + [URLQueryItem(name: "page", value: String(number))],
            as: ForgejoRunsPage.self
        )
        .flatMapAsync { page in
            let runs = found + page.workflowRuns
            guard !page.workflowRuns.isEmpty, runs.count < page.totalCount else {
                return .success(runs)
            }
            return await self.page(number + 1, of: path, query, runs)
        }
    }

    func run(in fullName: String, id: String) async -> Result<ForgejoRun, RunnersError> {
        await client.value(Self.repositoryPath(fullName) + ["actions", "runs", id])
    }

    /// A run's jobs, in one list, without their steps.
    func jobs(in fullName: String, runID: String) async -> Result<[ForgejoJob], RunnersError> {
        await client.value(Self.repositoryPath(fullName) + ["actions", "runs", runID, "jobs"])
    }

    /// One job with its steps.
    func job(in fullName: String, id: Int) async -> Result<ForgejoJob, RunnersError> {
        await client.value(Self.repositoryPath(fullName) + ["actions", "jobs", String(id)])
    }

    static let limit = URLQueryItem(name: "limit", value: String(pageSize))

    /// `repos/{owner}/{name}`
    static func repositoryPath(_ fullName: String) -> [String] {
        ["repos"] + fullName.split(separator: "/").map(String.init)
    }
}
