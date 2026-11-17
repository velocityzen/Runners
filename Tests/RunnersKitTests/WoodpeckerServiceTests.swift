import FPRetry
import Foundation
import Testing

@testable import RunnersKit

/// Shapes taken from ci.codeberg.org (Woodpecker 3.20), cut down to the fields `runners` reads
/// and a few it doesn't.
enum WoodpeckerFixtures {
    static func repository(
        _ name: String,
        owner: String = "acme",
        id: Int,
        active: Bool = true,
        lastPipeline: Int? = 7
    ) -> String {
        let last =
            lastPipeline.map {
                #", "last_pipeline": {"id": 1, "number": \#($0), "status": "success"}"#
            } ?? ""
        return """
            {"id": \(id), "forge_id": 1, "forge_remote_id": "16490", "org_id": 2, "owner": "\(owner)",
             "name": "\(name)", "full_name": "\(owner)/\(name)",
             "forge_url": "https://codeberg.org/\(owner)/\(name)", "private": false,
             "visibility": "public", "active": \(active), "allow_pr": true\(last)}
            """
    }

    static func pipeline(
        _ number: Int,
        status: String,
        started: Int = 0,
        workflows: [String]? = nil
    ) -> String {
        let flows = workflows.map { #", "workflows": [\#($0.joined(separator: ","))]"# } ?? ""
        return """
            {"id": \(number + 500000), "number": \(number), "author": "renovate-bot", "parent": 0,
             "event": "pull_request", "status": "\(status)", "created": 1800000000,
             "updated": 1800000000, "started": \(started), "finished": 0,
             "commit": "11bb6ca3c784", "branch": "main", "ref": "refs/pull/541/head",
             "title": "chore(deps): update a tag", "message": "chore(deps): update a tag\\n\\nbody",
             "sender": "mona", "forge_url": "https://codeberg.org/acme/app/pulls/541"\(flows)}
            """
    }

    static func workflow(
        _ id: Int,
        _ name: String,
        state: String,
        agent: Int = 0,
        steps: [(String, String)] = []
    ) -> String {
        let children = steps.enumerated().map { index, step in
            #"{"id": \#(id * 10 + index), "pid": \#(index + 3), "ppid": 1, "name": "\#(step.0)", "state": "\#(step.1)", "type": "commands"}"#
        }
        return """
            {"id": \(id), "pipeline_id": 1, "pid": 1, "name": "\(name)", "state": "\(state)",
             "started": \(state == "running" ? 1800000030 : 0), "finished": 0, "agent_id": \(agent),
             "platform": "linux/amd64", "children": [\(children.joined(separator: ","))]}
            """
    }

    static func list(_ items: [String]) -> HTTPResponse {
        .raw(200, "[" + items.joined(separator: ",") + "]")
    }
}

@Suite("Woodpecker service")
struct WoodpeckerServiceTests {
    func snapshot(
        _ query: StatusQuery = StatusQuery(),
        token: String = "t",
        _ respond: @escaping @Sendable (HTTPRequest) -> HTTPResponse?
    ) async -> (Result<StatusSnapshot, RunnersError>, StubTransport) {
        let stub = StubTransport { request, _ in
            switch request.url.path() {
                case "/api/user": return .raw(200, #"{"id": 9, "login": "mona", "admin": false}"#)
                case "/api/user/repos":
                    return WoodpeckerFixtures.list([
                        WoodpeckerFixtures.repository("app", id: 11),
                        WoodpeckerFixtures.repository("new", id: 12, lastPipeline: nil),
                        WoodpeckerFixtures.repository("dots", owner: "mona", id: 13),
                    ])
                default: return respond(request) ?? .raw(404, "")
            }
        }
        let service = WoodpeckerService(
            token: token,
            transport: stub,
            retryPolicy: .limitRetries(0)
        )
        let monitor = RunsMonitor(service: service, now: { Fixtures.now })
        return (await monitor.snapshot(query), stub)
    }

    @Test("maps statuses: pending is queued, blocked waits for approval, created is pending")
    func statuses() {
        #expect(RunStatus(woodpecker: "pending") == .queued)
        #expect(RunStatus(woodpecker: "running") == .running)
        #expect(RunStatus(woodpecker: "blocked") == .waiting)
        #expect(RunStatus(woodpecker: "created") == .pending)
        for finished in [
            "success", "failure", "error", "killed", "canceled", "declined", "skipped",
        ] {
            #expect(RunStatus(woodpecker: finished) == .completed)
        }
        #expect(Conclusion(woodpecker: "error") == .failure)
        #expect(Conclusion(woodpecker: "declined") == .cancelled)
        #expect(Conclusion(woodpecker: "killed") == .cancelled)
    }

    @Test("lists your repositories' unfinished pipelines, one request per status, with workflows")
    func activeRuns() async throws {
        let workflows = [
            WoodpeckerFixtures.workflow(
                1,
                "build",
                state: "running",
                agent: 33,
                steps: [("clone", "success"), ("test", "running")]
            ),
            WoodpeckerFixtures.workflow(2, "lint", state: "pending"),
        ]
        let (result, stub) = await snapshot { request in
            switch (request.url.path(), request.query("status")) {
                case ("/api/repos/11/pipelines", "running"):
                    WoodpeckerFixtures.list([
                        WoodpeckerFixtures.pipeline(1097, status: "running", started: 1800000020)
                    ])
                case ("/api/repos/11/pipelines", "blocked"):
                    WoodpeckerFixtures.list([WoodpeckerFixtures.pipeline(1101, status: "blocked")])
                case ("/api/repos/11/pipelines", _), ("/api/repos/13/pipelines", _):
                    WoodpeckerFixtures.list([])
                case ("/api/repos/11/pipelines/1097", _):
                    .raw(
                        200,
                        WoodpeckerFixtures.pipeline(
                            1097,
                            status: "running",
                            started: 1800000020,
                            workflows: workflows
                        )
                    )
                case ("/api/repos/11/pipelines/1101", _):
                    .raw(
                        200,
                        WoodpeckerFixtures.pipeline(
                            1101,
                            status: "blocked",
                            workflows: [WoodpeckerFixtures.workflow(3, "build", state: "blocked")]
                        )
                    )
                default: nil
            }
        }
        let snapshot = try result.get()
        #expect(snapshot.provider.id == "woodpecker")
        #expect(snapshot.owner == Owner(id: "9", login: "mona", kind: .user))
        #expect(snapshot.repositoryCount == 3)
        #expect(Set(snapshot.runs.map(\.run.status)) == [.running, .waiting])

        let running = try #require(snapshot.runs.first { $0.run.status == .running })
        #expect(running.run.id == "1097")
        #expect(running.run.title == "chore(deps): update a tag")
        #expect(running.run.actor == "mona")
        #expect(running.run.trigger == "pull_request")
        #expect(running.run.createdAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(running.run.startedAt == Date(timeIntervalSince1970: 1_800_000_020))
        #expect(
            running.run.webURL.absoluteString == "https://ci.codeberg.org/repos/11/pipeline/1097"
        )
        let jobs = try #require(running.jobs)
        #expect(jobs.map(\.name) == ["build", "lint"])
        #expect(jobs.map(\.status) == [.running, .queued])
        #expect(jobs[0].runner == "agent 33")
        #expect(jobs[0].currentStep == "test")
        #expect(jobs[0].startedAt == Date(timeIntervalSince1970: 1_800_000_030))
        #expect(jobs[1].runner == nil)
        #expect(jobs[1].labels == ["linux/amd64"])

        let listings = stub.requests.filter { $0.url.path().hasSuffix("/pipelines") }
        #expect(
            Set(listings.map { $0.url.path() }) == [
                "/api/repos/11/pipelines", "/api/repos/13/pipelines",
            ]
        )
        #expect(
            Set(listings.compactMap { $0.query("status") }) == [
                "running", "pending", "blocked", "created",
            ]
        )
        #expect(listings.count == 8)
        #expect(stub.requests.first?.headers["Authorization"] == "Bearer t")
    }

    @Test("pages through pipelines until a page comes back short")
    func paging() async throws {
        let query = StatusQuery(target: .owner("acme"), statuses: [.running], includeJobs: false)
        let (result, stub) = await snapshot(query) { request in
            guard request.url.path() == "/api/repos/11/pipelines" else { return nil }
            let page = Int(request.query("page") ?? "") ?? 0
            let count = page == 1 ? 50 : 3
            return WoodpeckerFixtures.list(
                (0..<count).map {
                    WoodpeckerFixtures.pipeline((page - 1) * 50 + $0 + 1, status: "running")
                }
            )
        }
        let snapshot = try result.get()
        #expect(snapshot.runs.count == 53)
        #expect(snapshot.owner?.login == "acme")
        #expect(snapshot.repositoryCount == 2)
        let pages = stub.requests.filter { $0.url.path() == "/api/repos/11/pipelines" }
        #expect(pages.map { $0.query("page") } == ["1", "2"])
        #expect(pages.allSatisfy { $0.query("perPage") == "50" })
    }

    @Test("says so when none of your repositories belong to the owner")
    func unknownOwner() async {
        let (result, _) = await snapshot(StatusQuery(target: .owner("nobody"))) { _ in nil }
        #expect(
            result.failure == .notFound("none of your Woodpecker repositories belong to nobody")
        )
    }

    @Test("reads public repositories by name without a token, and needs one for the rest")
    func anonymous() async throws {
        let query = StatusQuery(
            target: .repositories(["acme/app", "acme/gone"]),
            includeJobs: false
        )
        let (result, stub) = await snapshot(query, token: "") { request in
            switch request.url.path() {
                case "/api/repos/lookup/acme/app":
                    .raw(200, WoodpeckerFixtures.repository("app", id: 11))
                case "/api/repos/lookup/acme/gone": .raw(401, "")
                default: WoodpeckerFixtures.list([])
            }
        }
        #expect(
            result.failure
                == .notFound(
                    "no public Woodpecker repository named acme/gone; a private one needs WOODPECKER_TOKEN"
                )
        )
        #expect(stub.requests.allSatisfy { $0.headers["Authorization"] == nil })

        let (mine, _) = await snapshot(StatusQuery(), token: "") { _ in nil }
        guard case .tokenUnavailable(let reason) = mine.failure else {
            Issue.record("expected tokenUnavailable, got \(mine)")
            return
        }
        #expect(reason.contains("not your Codeberg token"))
    }

    @Test("says a rejected token must be Woodpecker's own")
    func rejected() async {
        let (result, _) = await snapshot(StatusQuery(target: .repositories(["acme/app"]))) { _ in
            .raw(401, "User not authorized")
        }
        #expect(
            result.failure
                == .unauthorized(
                    "User not authorized; WOODPECKER_TOKEN takes a personal access token from "
                        + "your user page on ci.codeberg.org, not a Codeberg or forge token"
                )
        )
    }

    @Test("reads a finished pipeline again, with its workflows")
    func latest() async throws {
        let stub = StubTransport { request, _ in
            request.url.path() == "/api/repos/11/pipelines/1097"
                ? .raw(
                    200,
                    WoodpeckerFixtures.pipeline(
                        1097,
                        status: "failure",
                        workflows: [WoodpeckerFixtures.workflow(1, "build", state: "failure")]
                    )
                ) : .raw(404, "")
        }
        let service = WoodpeckerService(token: "t", transport: stub, retryPolicy: .limitRetries(0))
        let repository = Repository(
            id: "11",
            name: "app",
            fullName: "acme/app",
            webURL: Fixtures.url("https://ci.codeberg.org/repos/11")
        )
        let running = WoodpeckerPipeline(
            id: 1,
            number: 1097,
            event: "push",
            status: "running",
            title: nil,
            message: "build",
            branch: "main",
            commit: nil,
            author: nil,
            sender: nil,
            created: 1_800_000_000,
            started: nil,
            finished: nil,
            workflows: nil
        )
        let latest = try await service.latest(
            ActiveRun(
                repository: repository,
                run: running.run(
                    webURL: Fixtures.url("https://ci.codeberg.org/repos/11/pipeline/1097")
                )
            ),
            query: StatusQuery()
        )
        .get()
        #expect(latest.run.conclusion == .failure)
        #expect(latest.jobs?.map(\.conclusion) == [.failure])
        #expect(stub.requests.count == 1)
    }

    @Test("turns a server into its API URL")
    func apiURL() {
        #expect(WoodpeckerService.defaultBaseURL.absoluteString == "https://ci.codeberg.org/api")
        #expect(
            WoodpeckerService.apiURL(forServer: "http://localhost:8000")?.absoluteString
                == "http://localhost:8000/api"
        )
        #expect(WoodpeckerService.apiURL(forServer: "") == nil)
    }
}
