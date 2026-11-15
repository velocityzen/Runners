import Foundation

@testable import RunnersKit

/// GitHub's wire shapes.
enum GitHubFixtures {
    static let me = GitHubAccount(id: 1, login: "octo", type: "User")
    static let org = GitHubAccount(id: 2, login: "acme", type: "Organization")

    static func repository(
        _ name: String,
        owner: GitHubAccount = me,
        id: Int? = nil,
        isFork: Bool = false,
        isArchived: Bool = false,
        isDisabled: Bool = false
    ) -> GitHubRepository {
        GitHubRepository(
            id: id ?? name.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF },
            name: name,
            fullName: "\(owner.login)/\(name)",
            owner: owner,
            isPrivate: false,
            isFork: isFork,
            isArchived: isArchived,
            isDisabled: isDisabled,
            htmlURL: Fixtures.url("https://github.com/\(owner.login)/\(name)")
        )
    }

    static func run(_ id: Int, _ status: String, minutesAgo minutes: Double = 5)
        -> GitHubWorkflowRun
    {
        GitHubWorkflowRun(
            id: id,
            name: "CI",
            displayTitle: "Commit \(id)",
            runNumber: id,
            runAttempt: 1,
            event: "push",
            status: status,
            conclusion: nil,
            headBranch: "main",
            headSHA: "abc\(id)",
            htmlURL: Fixtures.url("https://github.com/octo/repo/actions/runs/\(id)"),
            createdAt: Fixtures.minutesAgo(minutes),
            runStartedAt: Fixtures.minutesAgo(minutes),
            actor: me
        )
    }

    static func job(_ id: Int, _ name: String, _ status: String, runner: String? = nil)
        -> GitHubWorkflowJob
    {
        GitHubWorkflowJob(
            id: id,
            name: name,
            status: status,
            conclusion: nil,
            createdAt: Fixtures.minutesAgo(3),
            startedAt: nil,
            completedAt: nil,
            labels: ["ubuntu-latest"],
            runnerName: runner,
            htmlURL: nil,
            steps: nil
        )
    }

    static let rateLimit = GitHubRateLimit(limit: 5_000, remaining: 4_321, reset: 1_800_003_600)
}

/// Just enough of the GitHub REST API to serve the service, from in-memory data.
struct FakeGitHub: Sendable {
    var user = GitHubFixtures.me
    var accounts: [String: GitHubAccount] = [:]
    /// Repository lists by listing path, like `/orgs/acme/repos`.
    var listings: [String: [GitHubRepository]] = [:]
    var workflowCounts: [String: Int] = [:]
    /// Runs by repository full name, then GitHub status.
    var runs: [String: [String: [GitHubWorkflowRun]]] = [:]
    var jobs: [Int: [GitHubWorkflowJob]] = [:]
    var rateLimit: GitHubRateLimit? = GitHubFixtures.rateLimit
    /// Answers every request for runs with this instead.
    var runsFailure: HTTPResponse?

    func respond(_ request: HTTPRequest) -> HTTPResponse {
        let path = request.url.path()
        let parts = path.split(separator: "/").map(String.init)
        switch (parts.first, parts.count) {
            case ("user", 1): return .json(user)
            case ("rate_limit", 1):
                return rateLimit.map { .json(GitHubRateLimitResponse(resources: .init(core: $0))) }
                    ?? .notFound
            case (_, _) where parts.last == "repos":
                return listings[path].map { .json($0) } ?? .notFound
            case ("users", 2): return accounts[parts[1]].map { .json($0) } ?? .notFound
            case ("repos", 3...):
                return repositoryResource(parts[1] + "/" + parts[2], parts.dropFirst(3), request)
            default: return .notFound
        }
    }

    /// `/repos/{owner}/{name}/…`
    func repositoryResource(_ fullName: String, _ rest: ArraySlice<String>, _ request: HTTPRequest)
        -> HTTPResponse
    {
        switch rest.joined(separator: "/") {
            case "":
                listings.values.flatMap { $0 }.first { $0.fullName == fullName }.map { .json($0) }
                    ?? .notFound
            case "actions/workflows":
                .json(GitHubTotalCount(totalCount: workflowCounts[fullName] ?? 0))
            case "actions/runs":
                runsFailure
                    ?? .json(
                        GitHubWorkflowRunsPage(
                            workflowRuns: runs[fullName]?[request.query("status") ?? ""] ?? []
                        )
                    )
            case let resource where resource.hasSuffix("/jobs"):
                .json(
                    GitHubWorkflowJobsPage(
                        jobs: Int(rest.dropLast().last ?? "").flatMap { jobs[$0] } ?? []
                    )
                )
            default: .notFound
        }
    }

    func transport() -> StubTransport {
        StubTransport { request, _ in respond(request) }
    }
}
