import FPRetry
import Foundation
import Testing

@testable import RunnersKit

/// Shapes from Depot's API reference and depot/cli's `ci.proto`, in proto3 JSON: fields that
/// hold their default are left out.
enum DepotFixtures {
    static func run(
        _ id: String,
        repo: String = "acme/app",
        status: String = "running"
    ) -> String {
        """
        {"runId": "\(id)", "repo": "\(repo)", "trigger": "push", "sha": "aaa111",
         "headSha": "bbb222", "ref": "refs/heads/main", "status": "\(status)",
         "createdAt": "2027-01-15T08:00:00Z"}
        """
    }

    static func runs(_ runs: [String], next: String? = nil) -> HTTPResponse {
        let token = next.map { #", "nextPageToken": "\#($0)""# } ?? ""
        return .raw(200, #"{"runs": [\#(runs.joined(separator: ","))]\#(token)}"#)
    }

    static func job(_ id: String, _ key: String, status: String) -> String {
        #"{"jobId": "\#(id)", "jobKey": "\#(key)", "status": "\#(status)", "jobDisplayName": "\#(key)", "attempts": [{"attemptId": "a-\#(id)", "attempt": 1, "status": "\#(status)"}]}"#
    }

    static func workflow(
        _ id: String,
        name: String?,
        status: String,
        path: String = ".depot/workflows/ci.yml",
        jobs: [String] = []
    ) -> String {
        let named = name.map { #""name": "\#($0)", "# } ?? ""
        return """
            {"workflowId": "\(id)", \(named)"status": "\(status)", "workflowPath": "\(path)",
             "jobs": [\(jobs.joined(separator: ","))]}
            """
    }

    static func runStatus(_ id: String, status: String = "running", _ workflows: [String])
        -> HTTPResponse
    {
        .raw(
            200,
            #"{"orgId": "org1", "runId": "\#(id)", "status": "\#(status)", "workflows": [\#(workflows.joined(separator: ","))]}"#
        )
    }
}

extension HTTPRequest {
    /// The Connect method a request calls: `ListRuns`.
    var depotMethod: String {
        url.lastPathComponent
    }

    /// The request's JSON body.
    var depotBody: [String: Any] {
        (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: Any] ?? [:]
    }

    var depotStatuses: [String] {
        depotBody["status"] as? [String] ?? []
    }
}

@Suite("Depot CI service")
struct DepotCIServiceTests {
    func service(_ respond: @escaping @Sendable (HTTPRequest) -> HTTPResponse?) -> (
        DepotCIService, StubTransport
    ) {
        let stub = StubTransport { request, _ in respond(request) ?? .raw(404, "") }
        return (DepotCIService(token: "t", transport: stub, retryPolicy: .limitRetries(0)), stub)
    }

    func snapshot(
        _ query: StatusQuery = StatusQuery(),
        _ respond: @escaping @Sendable (HTTPRequest) -> HTTPResponse?
    ) async -> (Result<StatusSnapshot, RunnersError>, StubTransport) {
        let (service, stub) = service(respond)
        let monitor = RunsMonitor(service: service, now: { Fixtures.now })
        return (await monitor.snapshot(query), stub)
    }

    /// The organization's recent runs, which make its scope.
    static func recent(_ request: HTTPRequest) -> HTTPResponse? {
        guard request.depotMethod == "ListRuns", request.depotStatuses.count == 5 else {
            return nil
        }
        return DepotFixtures.runs([
            DepotFixtures.run("r1"),
            DepotFixtures.run("r0", status: "finished"),
            DepotFixtures.run("r9", repo: "acme/web", status: "failed"),
            DepotFixtures.run("r8", repo: "other/lib", status: "finished"),
        ])
    }

    @Test("maps statuses: a waiting job is held by a concurrency group, so pending")
    func statuses() {
        #expect(RunStatus(depotRun: "queued") == .queued)
        #expect(RunStatus(depotRun: "running") == .running)
        for finished in ["finished", "failed", "cancelled"] {
            #expect(RunStatus(depotRun: finished) == .completed)
        }
        #expect(RunStatus(depotRun: nil) == .unknown)
        #expect(RunStatus(depotJob: "waiting") == .pending)
        #expect(RunStatus(depotJob: "skipped") == .completed)
        #expect(RunStatus(depotJob: "queued") == .queued)
        #expect(Conclusion(depotStatus: "finished") == .success)
        #expect(Conclusion(depotStatus: "failed") == .failure)
        #expect(Conclusion(depotStatus: "cancelled") == .cancelled)
        #expect(Conclusion(depotStatus: "skipped") == .skipped)
        #expect(Conclusion(depotStatus: "running") == nil)
        #expect(Conclusion(depot: "timed_out") == .timedOut)
        #expect(Conclusion(depot: "success") == .success)
        #expect(Conclusion(depot: "") == nil)
        #expect(RunStatus.active.compactMap(\.depotQueryValue) == ["running", "queued"])
    }

    @Test("shows each unfinished workflow of the organization's runs, with its jobs")
    func activeRuns() async throws {
        let (result, stub) = await snapshot { request in
            if let recent = Self.recent(request) { return recent }
            switch request.depotMethod {
                case "ListRuns":
                    return DepotFixtures.runs([
                        DepotFixtures.run("r1"), DepotFixtures.run("r7", repo: "new/repo"),
                    ])
                case "GetRunStatus" where request.depotBody["runId"] as? String == "r1":
                    return DepotFixtures.runStatus(
                        "r1",
                        [
                            DepotFixtures.workflow(
                                "w1",
                                name: "Build",
                                status: "running",
                                jobs: [
                                    DepotFixtures.job("j1", "build", status: "running"),
                                    DepotFixtures.job("j2", "test", status: "waiting"),
                                    DepotFixtures.job("j3", "setup", status: "finished"),
                                ]
                            ),
                            DepotFixtures.workflow(
                                "w2",
                                name: nil,
                                status: "finished",
                                path: ".depot/workflows/lint.yml"
                            ),
                            DepotFixtures.workflow(
                                "w3",
                                name: nil,
                                status: "queued",
                                path: ".depot/workflows/deploy.yml"
                            ),
                        ]
                    )
                case "GetJob" where request.depotBody["jobId"] as? String == "j1":
                    return .raw(
                        200,
                        """
                        {"jobId": "j1", "jobKey": "build", "jobDisplayName": "Build app",
                         "jobStatus": "running", "jobCreatedAt": "2027-01-15T08:00:05Z",
                         "jobStartedAt": "2027-01-15T08:00:20.5Z",
                         "runsOn": {"labels": ["depot-ubuntu-24.04-4"], "cpus": 4, "memoryGb": 16}}
                        """
                    )
                case "GetJob" where request.depotBody["jobId"] as? String == "j2":
                    return .raw(
                        200,
                        """
                        {"jobId": "j2", "jobKey": "test", "jobStatus": "waiting",
                         "jobCreatedAt": "2027-01-15T08:00:05Z", "waitingReason": "concurrency",
                         "runsOn": {"labels": ["depot-ubuntu-24.04"]}}
                        """
                    )
                default: return nil
            }
        }
        let snapshot = try result.get()
        #expect(snapshot.provider.id == "depot-ci")
        #expect(snapshot.owner == nil)
        #expect(snapshot.repositoryCount == 3)
        #expect(snapshot.runs.map(\.run.id).sorted() == ["w1", "w3"])

        let build = try #require(snapshot.runs.first { $0.run.id == "w1" })
        #expect(build.repository.fullName == "acme/app")
        #expect(build.repository.webURL.absoluteString == "https://github.com/acme/app")
        #expect(build.run.name == "Build")
        #expect(build.run.status == .running)
        #expect(build.run.branch == "main")
        #expect(build.run.commit == "bbb222")
        #expect(build.run.trigger == "push")
        #expect(build.run.webURL.absoluteString == "https://depot.dev/orgs/org1/workflows/w1")
        #expect(build.run.createdAt == JSONCoding.parseDate("2027-01-15T08:00:00Z"))

        let jobs = try #require(build.jobs)
        #expect(jobs.map(\.name) == ["Build app", "test", "setup"])
        #expect(jobs.map(\.status) == [.running, .pending, .completed])
        #expect(jobs[0].runner == "4 CPUs, 16 GB")
        #expect(jobs[0].labels == ["depot-ubuntu-24.04-4"])
        #expect(jobs[0].runnerHost == .depot)
        #expect(jobs[0].startedAt == JSONCoding.parseDate("2027-01-15T08:00:20.5Z"))
        #expect(jobs[1].createdAt == JSONCoding.parseDate("2027-01-15T08:00:05Z"))
        #expect(jobs[2].conclusion == .success)
        #expect(jobs[2].startedAt == nil)

        let deploy = try #require(snapshot.runs.first { $0.run.id == "w3" })
        #expect(deploy.run.name == "deploy.yml")
        #expect(deploy.run.status == .queued)

        let listings = stub.requests.filter { $0.depotMethod == "ListRuns" }
        #expect(listings.map(\.depotStatuses) == [DepotRun.statuses, ["queued", "running"]])
        #expect(listings.allSatisfy { $0.depotBody["pageSize"] as? Int == 100 })
        #expect(listings.allSatisfy { $0.depotBody["repo"] == nil })
        // r7 is for a repository outside the scope, so it isn't read.
        #expect(
            stub.requests.filter { $0.depotMethod == "GetRunStatus" }.map {
                $0.depotBody["runId"] as? String
            } == ["r1"]
        )
        #expect(
            Set(
                stub.requests.filter { $0.depotMethod == "GetJob" }.compactMap {
                    $0.depotBody["jobId"] as? String
                }
            ) == ["j1", "j2"]
        )

        let request = try #require(stub.requests.first)
        #expect(request.method == "POST")
        #expect(
            request.url.absoluteString == "https://api.depot.dev/depot.ci.v1.CIService/ListRuns"
        )
        #expect(request.headers["Authorization"] == "Bearer t")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Connect-Protocol-Version"] == "1")
    }

    @Test("keeps an owner's repositories, by the owner in their names")
    func owner() async throws {
        let query = StatusQuery(target: .owner("ACME"), includeJobs: false)
        let (result, _) = await snapshot(query) { request in
            if let recent = Self.recent(request) { return recent }
            switch request.depotMethod {
                case "ListRuns":
                    return DepotFixtures.runs([
                        DepotFixtures.run("r1"), DepotFixtures.run("r8", repo: "other/lib"),
                    ])
                case "GetRunStatus":
                    let id = request.depotBody["runId"] as? String ?? ""
                    return DepotFixtures.runStatus(
                        id,
                        [DepotFixtures.workflow("w-\(id)", name: "CI", status: "running")]
                    )
                default: return nil
            }
        }
        let snapshot = try result.get()
        #expect(snapshot.owner?.login == "ACME")
        #expect(snapshot.repositoryCount == 2)
        #expect(snapshot.runs.map(\.run.id) == ["w-r1"])
        #expect(snapshot.runs.first?.jobs == nil)
    }

    @Test("lists each repository named with --repo by itself, paging by token")
    func repositories() async throws {
        let query = StatusQuery(
            target: .repositories(["acme/app", "acme/web"]),
            statuses: [.running],
            includeJobs: false
        )
        let (result, stub) = await snapshot(query) { request in
            switch (request.depotMethod, request.depotBody["repo"] as? String) {
                case ("ListRuns", "acme/app"):
                    return request.depotBody["pageToken"] as? String == "p2"
                        ? DepotFixtures.runs([DepotFixtures.run("r2")], next: "")
                        : DepotFixtures.runs([DepotFixtures.run("r1")], next: "p2")
                case ("ListRuns", "acme/web"): return .raw(200, "{}")
                case ("GetRunStatus", _):
                    let id = request.depotBody["runId"] as? String ?? ""
                    return DepotFixtures.runStatus(
                        id,
                        [DepotFixtures.workflow("w-\(id)", name: "CI", status: "running")]
                    )
                default: return nil
            }
        }
        let snapshot = try result.get()
        #expect(snapshot.repositoryCount == 2)
        #expect(snapshot.runs.map(\.run.id).sorted() == ["w-r1", "w-r2"])
        let listings = stub.requests.filter { $0.depotMethod == "ListRuns" }
        #expect(listings.count == 3)
        #expect(listings.allSatisfy { $0.depotStatuses == ["running"] })
        #expect(
            listings.filter { $0.depotBody["repo"] as? String == "acme/app" }.map {
                $0.depotBody["pageToken"] as? String
            } == [nil, "p2"]
        )
    }

    @Test("asks for nothing when no status asked for is one a Depot run has")
    func noRunStatus() async throws {
        let query = StatusQuery(target: .repositories(["acme/app"]), statuses: [.waiting])
        let (result, stub) = await snapshot(query) { _ in nil }
        #expect(try result.get().runs.isEmpty)
        #expect(stub.requests.isEmpty)
    }

    @Test(
        "reads Connect errors: a rejected token says which one Depot wants",
        arguments: [
            (401, "unauthenticated", "invalid token"),
            (403, "permission_denied", "not allowed"),
            (404, "not_found", "run not found"),
            (503, "unavailable", "try again"),
        ]
    )
    func errors(_ status: Int, _ code: String, _ message: String) async {
        let (result, stub) = await snapshot(StatusQuery(target: .repositories(["acme/app"]))) {
            _ in .raw(status, #"{"code": "\#(code)", "message": "\#(message)"}"#)
        }
        let expected: RunnersError =
            switch code {
                case "unauthenticated":
                    .unauthorized(
                        "invalid token; DEPOT_TOKEN takes an organization API token, from "
                            + "Settings → API Tokens in the Depot dashboard"
                    )
                case "permission_denied": .forbidden(message)
                case "not_found": .notFound(message)
                default: .server(status: status, message: message)
            }
        #expect(result.failure == expected)
        #expect(stub.requests.count == 1)
    }

    @Test("reads a workflow again once it drops out, from its latest execution")
    func latest() async throws {
        let (service, stub) = service { request in
            guard request.depotMethod == "GetWorkflow" else { return nil }
            return .raw(
                200,
                """
                {"orgId": "org1", "runId": "r1", "repo": "acme/app", "ref": "refs/heads/main",
                 "sha": "aaa111", "trigger": "push", "runStatus": "failed",
                 "runCreatedAt": "2027-01-15T08:00:00Z", "workflowId": "w1",
                 "workflowName": "Build", "workflowStatus": "failed",
                 "workflowCreatedAt": "2027-01-15T08:00:01Z",
                 "workflowStartedAt": "2027-01-15T08:00:10Z",
                 "workflowFinishedAt": "2027-01-15T08:04:10Z",
                 "executions": [
                   {"executionId": "e1", "execution": 1, "status": "failed",
                    "jobs": [{"jobId": "j0", "jobKey": "build", "status": "failed"}]},
                   {"executionId": "e2", "execution": 2, "status": "failed",
                    "jobs": [{"jobId": "j1", "jobKey": "build", "status": "failed",
                              "startedAt": "2027-01-15T08:00:20Z",
                              "finishedAt": "2027-01-15T08:04:00Z"},
                             {"jobId": "j2", "jobKey": "deploy", "status": "skipped"}]}
                 ]}
                """
            )
        }
        let running = DepotWorkflowRun(
            orgID: "org1",
            workflowID: "w1",
            name: "Build",
            path: nil,
            status: "running",
            trigger: "push",
            ref: "refs/heads/main",
            commit: "aaa111",
            createdAt: Fixtures.now
        )
        let latest = try await service.latest(
            ActiveRun(repository: Repository(gitHubFullName: "acme/app"), run: running.run),
            query: StatusQuery()
        )
        .get()
        #expect(stub.requests.map { $0.depotBody["workflowId"] as? String } == ["w1"])
        #expect(latest.run.status == .completed)
        #expect(latest.run.conclusion == .failure)
        #expect(latest.run.completedAt == JSONCoding.parseDate("2027-01-15T08:04:10Z"))
        #expect(latest.jobs?.map(\.id) == ["j1", "j2"])
        #expect(latest.jobs?.map(\.conclusion) == [.failure, .skipped])
        #expect(latest.jobs?.first?.completedAt == JSONCoding.parseDate("2027-01-15T08:04:00Z"))
    }
}
