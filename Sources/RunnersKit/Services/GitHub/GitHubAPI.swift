import FP
import Foundation

/// The GitHub REST endpoints the service reads, answering in GitHub's own shapes.
struct GitHubAPI: Sendable {
    /// The API version these shapes are written against.
    static let version = "2026-03-10"

    let client: APIClient

    static func headers(token: String) -> [String: String] {
        [
            "Accept": "application/vnd.github+json",
            "Authorization": "Bearer \(token)",
            "User-Agent": "Runners",
            "X-GitHub-Api-Version": version,
        ]
    }

    /// GitHub answers its secondary rate limit with 403, not always with a `Retry-After`.
    @Sendable
    static func classify(_ response: HTTPResponse, url: URL) -> RunnersError {
        let error = RunnersError(response: response, url: url)
        guard case .forbidden(let message) = error,
            response.retryAfter != nil || message.localizedStandardContains("secondary rate limit")
        else { return error }
        return .throttled(retryAfter: response.retryAfter)
    }

    /// The user the token belongs to.
    func authenticatedUser() async -> Result<GitHubAccount, RunnersError> {
        await client.value(["user"])
    }

    func account(_ login: String) async -> Result<GitHubAccount, RunnersError> {
        await client.value(["users", login])
    }

    /// A repository by `owner/name`.
    func repository(_ fullName: String) async -> Result<GitHubRepository, RunnersError> {
        await client.value(Self.repositoryPath(fullName))
    }

    func repositories(_ listing: GitHubListing) async -> Result<[GitHubRepository], RunnersError> {
        await client.all(listing.path, listing.query, as: [GitHubRepository].self)
    }

    /// How many workflows a repository has. One request, however many there are.
    func workflowCount(in fullName: String) async -> Result<Int, RunnersError> {
        await client.value(
            Self.repositoryPath(fullName) + ["actions", "workflows"],
            [URLQueryItem(name: "per_page", value: "1")],
            as: GitHubTotalCount.self
        )
        .map(\.totalCount)
    }

    /// Runs with one status; GitHub filters by a single status per request.
    func workflowRuns(
        in fullName: String,
        status: String
    ) async -> Result<[GitHubWorkflowRun], RunnersError> {
        await client.all(
            Self.repositoryPath(fullName) + ["actions", "runs"],
            [
                URLQueryItem(name: "status", value: status),
                URLQueryItem(name: "exclude_pull_requests", value: "true"),
                .perPage,
            ],
            as: GitHubWorkflowRunsPage.self
        )
    }

    /// The jobs of a run's latest attempt.
    func jobs(in fullName: String, runID: String) async -> Result<[GitHubWorkflowJob], RunnersError>
    {
        await client.all(
            Self.repositoryPath(fullName) + ["actions", "runs", runID, "jobs"],
            [URLQueryItem(name: "filter", value: "latest"), .perPage],
            as: GitHubWorkflowJobsPage.self
        )
    }

    func rateLimit() async -> Result<GitHubRateLimit, RunnersError> {
        await client.value(["rate_limit"], as: GitHubRateLimitResponse.self)
            .map(\.resources.core)
    }

    /// `repos/{owner}/{name}`
    static func repositoryPath(_ fullName: String) -> [String] {
        ["repos"] + fullName.split(separator: "/").map(String.init)
    }
}

/// Any list response, read only for its size.
struct GitHubTotalCount: Codable {
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
    }
}
