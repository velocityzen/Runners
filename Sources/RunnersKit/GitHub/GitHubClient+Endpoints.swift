import FP
import Foundation

/// Where to list an account's repositories.
public enum RepositoryListing: Sendable, Equatable {
    /// Repositories the token's user owns, private ones included.
    case authenticatedUser
    case organization(String)
    /// Another user's public repositories.
    case user(String)

    /// The listing that sees the most of `owner`'s repositories as `viewer`.
    public static func of(_ owner: Account, viewer: Account) -> RepositoryListing {
        if owner.kind == .organization { return .organization(owner.login) }
        return owner.isSameAccount(as: viewer) ? .authenticatedUser : .user(owner.login)
    }

    var path: String {
        switch self {
            case .authenticatedUser: "user/repos"
            case .organization(let login): "orgs/\(login)/repos"
            case .user(let login): "users/\(login)/repos"
        }
    }

    var query: [URLQueryItem] {
        let filter =
            switch self {
                case .authenticatedUser: URLQueryItem(name: "affiliation", value: "owner")
                case .organization: URLQueryItem(name: "type", value: "all")
                case .user: URLQueryItem(name: "type", value: "owner")
            }
        return [filter, .perPage]
    }
}

public extension GitHubClient {
    /// The user the token belongs to.
    func authenticatedUser() async -> Result<Account, GitHubError> {
        await value("user")
    }

    func account(_ login: String) async -> Result<Account, GitHubError> {
        await value("users/\(login)")
    }

    /// A repository by `owner/name`.
    func repository(_ fullName: String) async -> Result<Repository, GitHubError> {
        await value("repos/\(fullName)")
    }

    func repositories(_ listing: RepositoryListing) async -> Result<[Repository], GitHubError> {
        await all(listing.path, listing.query, as: [Repository].self)
    }

    /// How many workflows a repository has. One request, however many there are.
    func workflowCount(in repository: Repository) async -> Result<Int, GitHubError> {
        await value(
            "repos/\(repository.fullName)/actions/workflows",
            [URLQueryItem(name: "per_page", value: "1")],
            as: TotalCount.self
        )
        .map(\.totalCount)
    }

    func workflowRuns(
        in repository: Repository,
        status: ActionStatus
    ) async -> Result<[WorkflowRun], GitHubError> {
        await all(
            "repos/\(repository.fullName)/actions/runs",
            [
                URLQueryItem(name: "status", value: status.rawValue),
                URLQueryItem(name: "exclude_pull_requests", value: "true"),
                .perPage,
            ],
            as: WorkflowRunsPage.self
        )
    }

    /// The jobs of a run's latest attempt.
    func jobs(of run: WorkflowRun, in repository: Repository) async -> Result<[WorkflowJob], GitHubError> {
        await all(
            "repos/\(repository.fullName)/actions/runs/\(run.id)/jobs",
            [URLQueryItem(name: "filter", value: "latest"), .perPage],
            as: WorkflowJobsPage.self
        )
    }

    /// The core quota. Asking for it does not use it up.
    func rateLimit() async -> Result<RateLimit, GitHubError> {
        await value("rate_limit", as: RateLimitResponse.self)
            .map(\.resources.core)
    }
}

/// Any list response, read only for its size.
struct TotalCount: Decodable {
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
    }
}

extension URLQueryItem {
    static let perPage = URLQueryItem(name: "per_page", value: "100")
}
