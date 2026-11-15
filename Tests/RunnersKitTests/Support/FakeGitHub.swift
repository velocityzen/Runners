import Foundation

@testable import RunnersKit

/// Just enough of the REST API to serve the monitor, from in-memory data.
struct FakeGitHub: Sendable {
    var user = Fixtures.me
    var accounts: [String: Account] = [:]
    /// Repository lists by listing path, like `/orgs/acme/repos`.
    var listings: [String: [Repository]] = [:]
    var workflowCounts: [String: Int] = [:]
    /// Runs by repository full name, then status.
    var runs: [String: [ActionStatus: [WorkflowRun]]] = [:]
    var jobs: [Int: [WorkflowJob]] = [:]
    var rateLimit: RateLimit? = Fixtures.rateLimit
    /// Answers every request for runs with this instead.
    var runsFailure: HTTPResponse?

    var repositories: [Repository] {
        listings.values.flatMap { $0 }
    }

    func respond(_ request: HTTPRequest) -> HTTPResponse {
        let path = request.url.path()
        let parts = path.split(separator: "/").map(String.init)
        switch (parts.first, parts.count) {
            case ("user", 1): return .json(user)
            case ("rate_limit", 1): return rateLimit.map { .json(RateLimitBody($0)) } ?? .notFound
            case (_, _) where parts.last == "repos": return listings[path].map { .json($0) } ?? .notFound
            case ("users", 2): return accounts[parts[1]].map { .json($0) } ?? .notFound
            case ("repos", 3...): return repositoryResource(parts[1] + "/" + parts[2], parts.dropFirst(3), request)
            default: return .notFound
        }
    }

    /// `/repos/{owner}/{name}/…`
    func repositoryResource(_ fullName: String, _ rest: ArraySlice<String>, _ request: HTTPRequest) -> HTTPResponse {
        switch rest.joined(separator: "/") {
            case "": repository(fullName).map { .json($0) } ?? .notFound
            case "actions/workflows": .json(CountBody(total_count: workflowCounts[fullName] ?? 0))
            case "actions/runs": runsFailure ?? .json(RunsBody(runs(of: fullName, request.query("status"))))
            case let resource where resource.hasSuffix("/jobs"):
                .json(JobsBody(Int(rest.dropLast().last ?? "").flatMap { jobs[$0] } ?? []))
            default: .notFound
        }
    }

    func repository(_ fullName: String) -> Repository? {
        repositories.first { $0.fullName == fullName }
    }

    func runs(of fullName: String, _ status: String?) -> [WorkflowRun] {
        status.flatMap(ActionStatus.init(rawValue:)).flatMap { runs[fullName]?[$0] } ?? []
    }

    func transport() -> StubTransport {
        StubTransport { request, _ in respond(request) }
    }
}
