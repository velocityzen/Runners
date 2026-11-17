import FPRetry
import Foundation
import Testing

@testable import RunnersKit

/// Shapes taken from Codeberg (Forgejo 17), cut down to the fields `runners` reads and a few
/// it doesn't.
enum ForgejoFixtures {
    static func repository(
        _ name: String,
        owner: String = "acme",
        id: Int,
        hasActions: Bool = true,
        archived: Bool = false,
        fork: Bool = false
    ) -> String {
        """
        {"id": \(id), "owner": {"id": 7, "login": "\(owner)", "full_name": "Acme"},
         "name": "\(name)", "full_name": "\(owner)/\(name)", "empty": false, "private": false,
         "fork": \(fork), "mirror": false, "archived": \(archived), "has_actions": \(hasActions),
         "html_url": "https://codeberg.org/\(owner)/\(name)", "default_branch": "main"}
        """
    }

    static func run(
        _ id: Int,
        number: Int,
        status: String,
        repository: String = "acme/app",
        needApproval: Bool = false,
        approvedBy: Int = 0,
        started: String = "null"
    ) -> String {
        """
        {"id": \(id), "title": "fix the build", "repository": {"id": 1, "full_name": "\(repository)"},
         "workflow_id": "testing.yml", "index_in_repo": \(number),
         "trigger_user": {"id": 9, "login": "mona"}, "ScheduleID": 0, "prettyref": "#15054",
         "is_ref_deleted": false, "commit_sha": "6f69300797fd", "is_fork_pull_request": \(needApproval),
         "need_approval": \(needApproval), "approved_by": \(approvedBy), "event": "pull_request",
         "event_payload": "{\\"action\\":\\"synchronized\\"}", "trigger_event": "pull_request",
         "status": "\(status)", "started": \(started), "stopped": null,
         "created": "2027-01-15T08:00:00+01:00", "updated": "2027-01-15T08:00:00+01:00",
         "html_url": "https://codeberg.org/\(repository)/actions/runs/\(number)"}
        """
    }

    static func runs(_ runs: [String], total: Int? = nil) -> HTTPResponse {
        .raw(
            200,
            #"{"workflow_runs": [\#(runs.joined(separator: ","))], "total_count": \#(total ?? runs.count)}"#
        )
    }

    /// A run's job list leaves out steps.
    static func job(_ id: Int, _ name: String, _ status: String, taskID: Int = 0) -> String {
        """
        {"id": \(id), "run_id": 100, "attempt": 1, "handle": "bf45f1d8", "repo_id": 1,
         "owner_id": 7, "name": "\(name)",
         "html_url": "https://codeberg.org/acme/app/actions/runs/217/jobs/0/attempt/1",
         "needs": null, "runs_on": ["docker"], "task_id": \(taskID), "status": "\(status)"}
        """
    }

    /// A job read on its own has its steps.
    static let runningJob = """
        {"id": 11, "run_id": 100, "attempt": 1, "handle": "20acfd4e", "repo_id": 1, "owner_id": 7,
         "name": "backend-checks", "html_url": "https://codeberg.org/acme/app/actions/runs/217/jobs/0/attempt/1",
         "needs": null, "runs_on": ["docker"], "task_id": 11792428, "status": "running",
         "steps": [
          {"number": 0, "name": "Set up job", "status": "success",
           "started": "2027-01-15T08:00:12+01:00", "stopped": "2027-01-15T08:00:17+01:00"},
          {"number": 1, "name": "checkout", "status": "success",
           "started": "2027-01-15T08:00:17+01:00", "stopped": "2027-01-15T08:00:41+01:00"},
          {"number": 2, "name": "make test", "status": "running",
           "started": "2027-01-15T08:00:41+01:00", "stopped": null},
          {"number": 3, "name": "Complete job", "status": "waiting", "started": null, "stopped": null}
         ]}
        """
}

@Suite("Forgejo service")
struct ForgejoServiceTests {
    func snapshot(
        _ query: StatusQuery = StatusQuery(target: .owner("acme")),
        token: String = "t",
        _ respond: @escaping @Sendable (HTTPRequest) -> HTTPResponse?
    ) async -> (Result<StatusSnapshot, RunnersError>, StubTransport) {
        let stub = StubTransport { request, _ in
            let path = String(request.url.path().dropFirst("/api/v1".count))
            switch path {
                case "/orgs/acme":
                    return .raw(200, #"{"id": 7, "username": "acme", "name": "acme"}"#)
                case "/orgs/acme/repos":
                    return .raw(
                        200,
                        "["
                            + [
                                ForgejoFixtures.repository("app", id: 1),
                                ForgejoFixtures.repository("site", id: 2, hasActions: false),
                                ForgejoFixtures.repository("old", id: 3, archived: true),
                                ForgejoFixtures.repository("fork", id: 4, fork: true),
                            ]
                            .joined(separator: ",") + "]"
                    )
                default: return respond(request) ?? .notFound
            }
        }
        let service = ForgejoService(token: token, transport: stub, retryPolicy: .limitRetries(0))
        let monitor = RunsMonitor(service: service, now: { Fixtures.now })
        return (await monitor.snapshot(query), stub)
    }

    @Test("maps runs: approval, blocked, waiting and running, by Forgejo's statuses")
    func runStatuses() throws {
        func status(_ json: String) throws -> RunStatus {
            try JSONCoding.decode(ForgejoRun.self, from: Data(json.utf8)).get().run.status
        }
        #expect(try status(ForgejoFixtures.run(1, number: 1, status: "running")) == .running)
        #expect(try status(ForgejoFixtures.run(2, number: 2, status: "waiting")) == .queued)
        #expect(try status(ForgejoFixtures.run(3, number: 3, status: "blocked")) == .pending)
        let approval = ForgejoFixtures.run(4, number: 4, status: "blocked", needApproval: true)
        #expect(try status(approval) == .waiting)
        let older = ForgejoFixtures.run(5, number: 5, status: "waiting", needApproval: true)
        #expect(try status(older) == .waiting)
        let approved = ForgejoFixtures.run(
            6,
            number: 6,
            status: "waiting",
            needApproval: true,
            approvedBy: 9
        )
        #expect(try status(approved) == .queued)
        #expect(try status(ForgejoFixtures.run(7, number: 7, status: "success")) == .completed)
    }

    @Test("maps a run's fields the way the other services do")
    func runFields() throws {
        let raw = ForgejoFixtures.run(
            100,
            number: 217,
            status: "running",
            started: #""2027-01-15T08:00:10+01:00""#
        )
        let run = try JSONCoding.decode(ForgejoRun.self, from: Data(raw.utf8)).get().run
        #expect(run.id == "100")
        #expect(run.number == 217)
        #expect(run.name == "testing.yml")
        #expect(run.title == "fix the build")
        #expect(run.branch == "#15054")
        #expect(run.trigger == "pull_request")
        #expect(run.actor == "mona")
        #expect(run.webURL.absoluteString == "https://codeberg.org/acme/app/actions/runs/217")
        #expect(run.createdAt == JSONCoding.parseDate("2027-01-15T07:00:00Z"))
        #expect(run.startedAt == JSONCoding.parseDate("2027-01-15T07:00:10Z"))
        #expect(run.conclusion == nil)
    }

    @Test("lists the owner's repositories that can run Actions, then their unfinished runs")
    func activeRuns() async throws {
        let (result, stub) = await snapshot { request in
            switch request.url.path() {
                case "/api/v1/repos/acme/app/actions/runs":
                    ForgejoFixtures.runs([
                        ForgejoFixtures.run(100, number: 217, status: "running"),
                        ForgejoFixtures.run(
                            101,
                            number: 218,
                            status: "blocked",
                            needApproval: true
                        ),
                    ])
                case "/api/v1/repos/acme/app/actions/runs/100/jobs":
                    .raw(
                        200,
                        "["
                            + [
                                ForgejoFixtures.job(11, "backend-checks", "running", taskID: 5),
                                ForgejoFixtures.job(12, "test-unit", "blocked"),
                                ForgejoFixtures.job(13, "lint", "success", taskID: 6),
                            ]
                            .joined(separator: ",") + "]"
                    )
                case "/api/v1/repos/acme/app/actions/runs/101/jobs":
                    .raw(200, "[" + ForgejoFixtures.job(21, "preview", "blocked") + "]")
                case "/api/v1/repos/acme/app/actions/jobs/11": .raw(200, ForgejoFixtures.runningJob)
                default: nil
            }
        }
        let snapshot = try result.get()
        #expect(snapshot.provider.id == "forgejo")
        #expect(snapshot.owner == Owner(id: "7", login: "acme", kind: .organization))
        #expect(snapshot.repositoryCount == 4)
        #expect(snapshot.runs.map(\.run.status) == [.waiting, .running])
        #expect(snapshot.rateLimit == nil)

        let jobs = try #require(snapshot.runs.last?.jobs)
        #expect(jobs.map(\.status) == [.running, .pending, .completed])
        #expect(jobs[0].startedAt == JSONCoding.parseDate("2027-01-15T07:00:12Z"))
        #expect(jobs[0].currentStep == "make test")
        #expect(jobs[1].labels == ["docker"])
        #expect(jobs[1].createdAt == JSONCoding.parseDate("2027-01-15T07:00:00Z"))
        #expect(jobs[2].conclusion == .success)

        let runsRequests = stub.requests.filter { $0.url.path().hasSuffix("/actions/runs") }
        #expect(runsRequests.map { $0.url.path() } == ["/api/v1/repos/acme/app/actions/runs"])
        #expect(runsRequests.first?.queryValues("status") == ["blocked", "running", "waiting"])
        #expect(
            stub.paths.filter { $0.contains("/actions/jobs/") } == [
                "/api/v1/repos/acme/app/actions/jobs/11"
            ]
        )
    }

    @Test("pages through runs by the total in the body, which has no Link header")
    func paging() async throws {
        let (result, stub) = await snapshot(StatusQuery(target: .owner("acme"), includeJobs: false))
        {
            request in
            guard request.url.path() == "/api/v1/repos/acme/app/actions/runs" else { return nil }
            let page = Int(request.query("page") ?? "") ?? 0
            let runs = (0..<(page == 3 ? 1 : 50)).map { index in
                let id = (page - 1) * 50 + index + 1
                return ForgejoFixtures.run(id, number: id, status: "running")
            }
            return ForgejoFixtures.runs(runs, total: 101)
        }
        #expect(try result.get().runs.count == 101)
        let pages = stub.requests.filter { $0.url.path().hasSuffix("/actions/runs") }
        #expect(pages.map { $0.query("page") } == ["1", "2", "3"])
        #expect(pages.allSatisfy { $0.query("limit") == "50" })
    }

    @Test("asks only for the statuses the query wants, and keeps only those runs")
    func statuses() async throws {
        let query = StatusQuery(target: .owner("acme"), statuses: [.queued], includeJobs: false)
        let (result, stub) = await snapshot(query) { request in
            request.url.path() == "/api/v1/repos/acme/app/actions/runs"
                ? ForgejoFixtures.runs([
                    ForgejoFixtures.run(1, number: 1, status: "waiting"),
                    ForgejoFixtures.run(2, number: 2, status: "waiting", needApproval: true),
                ]) : nil
        }
        #expect(try result.get().runs.map(\.run.id) == ["1"])
        let request = stub.requests.first { $0.url.path().hasSuffix("/actions/runs") }
        #expect(request?.queryValues("status") == ["waiting"])
    }

    @Test("sends the token as Forgejo takes it, or none")
    func headers() {
        #expect(ForgejoAPI.headers(token: "abc")["Authorization"] == "token abc")
        #expect(ForgejoAPI.headers(token: "")["Authorization"] == nil)
    }

    @Test("names a user's repositories when no organization has the name")
    func user() async throws {
        let (result, stub) = await snapshot(StatusQuery(target: .owner("mona"))) { request in
            switch request.url.path() {
                case "/api/v1/users/mona": .raw(200, #"{"id": 9, "login": "mona"}"#)
                case "/api/v1/users/mona/repos":
                    .raw(200, "[" + ForgejoFixtures.repository("dots", owner: "mona", id: 5) + "]")
                case "/api/v1/repos/mona/dots/actions/runs": ForgejoFixtures.runs([])
                default: nil
            }
        }
        #expect(try result.get().owner == Owner(id: "9", login: "mona", kind: .user))
        #expect(stub.paths.prefix(2) == ["/api/v1/orgs/mona", "/api/v1/users/mona"])
    }

    @Test("says plainly when there is no such owner")
    func missingOwner() async {
        let (result, _) = await snapshot(StatusQuery(target: .owner("nobody"))) { _ in nil }
        #expect(result.failure == .notFound("no Forgejo organization or user named nobody"))
    }

    @Test("keeps only the user's own repositories, which /user/repos mixes with others")
    func authenticatedUser() async throws {
        let (result, _) = await snapshot(StatusQuery()) { request in
            switch request.url.path() {
                case "/api/v1/user": .raw(200, #"{"id": 9, "login": "mona"}"#)
                case "/api/v1/user/repos":
                    .raw(
                        200,
                        "["
                            + ForgejoFixtures.repository("dots", owner: "mona", id: 5) + ","
                            + ForgejoFixtures.repository("app", owner: "acme", id: 1) + "]"
                    )
                case "/api/v1/repos/mona/dots/actions/runs": ForgejoFixtures.runs([])
                default: nil
            }
        }
        let snapshot = try result.get()
        #expect(snapshot.repositoryCount == 1)
        #expect(snapshot.owner?.login == "mona")
    }

    @Test("needs a token to know whose repositories to read")
    func anonymous() async {
        let (result, stub) = await snapshot(StatusQuery(), token: "") { _ in nil }
        guard case .tokenUnavailable(let reason) = result.failure else {
            Issue.record("expected tokenUnavailable, got \(result)")
            return
        }
        #expect(reason.contains("FORGEJO_TOKEN"))
        #expect(stub.requests.isEmpty)
    }

    @Test("reads a finished run again, with its jobs")
    func latest() async throws {
        let stub = StubTransport { request, _ in
            switch request.url.path() {
                case "/api/v1/repos/acme/app/actions/runs/100":
                    .raw(200, ForgejoFixtures.run(100, number: 217, status: "failure"))
                case "/api/v1/repos/acme/app/actions/runs/100/jobs":
                    .raw(200, "[" + ForgejoFixtures.job(11, "build", "failure", taskID: 5) + "]")
                default: .notFound
            }
        }
        let service = ForgejoService(token: "t", transport: stub, retryPolicy: .limitRetries(0))
        let repository = Repository(
            id: "1",
            name: "app",
            fullName: "acme/app",
            webURL: Fixtures.url("https://codeberg.org/acme/app")
        )
        let raw = ForgejoFixtures.run(100, number: 217, status: "running")
        let running = try JSONCoding.decode(ForgejoRun.self, from: Data(raw.utf8)).get()
        let latest = try await service.latest(
            ActiveRun(repository: repository, run: running.run),
            query: StatusQuery()
        )
        .get()
        #expect(latest.run.status == .completed)
        #expect(latest.run.conclusion == .failure)
        #expect(latest.jobs?.map(\.conclusion) == [.failure])
    }

    @Test("turns a host into its API URL")
    func apiURL() {
        #expect(ForgejoService.defaultBaseURL.absoluteString == "https://codeberg.org/api/v1")
        #expect(
            ForgejoService.apiURL(forHost: "http://localhost:3000")?.absoluteString
                == "http://localhost:3000/api/v1"
        )
        #expect(ForgejoService.apiURL(forHost: "") == nil)
    }
}
