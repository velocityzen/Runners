import FPRetry
import Foundation
import Testing

@testable import RunnersKit

/// Shapes from depot/proto's `depot/core/v1/github_actions.proto`, in proto3 JSON: enums by
/// name, 64-bit integers as strings, fields at their default left out.
enum DepotGitHubFixtures {
    static func job(
        _ id: String,
        run: String = "100",
        repo: String = "acme/app",
        name: String? = nil,
        status: String = "RUNNING",
        conclusion: String? = nil,
        created: String = "2027-01-15T07:58:00Z",
        started: String? = "2027-01-15T07:58:12.123456789Z",
        finished: String? = nil
    ) -> String {
        let fields: [String?] = [
            #""jobId": "\#(id)""#,
            #""runId": "\#(run)""#,
            #""repository": "\#(repo)""#,
            #""name": "\#(name ?? "job \(id)")""#,
            #""workflowName": "CI""#,
            #""workflowPath": ".github/workflows/ci.yml""#,
            #""status": "GITHUB_ACTIONS_JOB_STATUS_\#(status)""#,
            conclusion.map { #""conclusion": "GITHUB_ACTIONS_JOB_CONCLUSION_\#($0)""# },
            #""runnerLabel": "depot-ubuntu-24.04-4""#,
            #""requestedOs": "linux""#,
            #""requestedArchitecture": "amd64""#,
            #""requestedCpuCount": 4"#,
            #""requestedMemoryGib": 16"#,
            #""githubUrl": "https://github.com/\#(repo)/actions/runs/\#(run)/job/\#(id)""#,
            #""createdAt": "\#(created)""#,
            started.map { #""startedAt": "\#($0)""# },
            finished.map { #""finishedAt": "\#($0)""# },
            started == nil ? nil : #""queueSeconds": "12""#,
        ]
        return "{" + fields.compactMap(\.self).joined(separator: ", ") + "}"
    }

    static func jobs(_ jobs: [String], next: String? = nil) -> HTTPResponse {
        let token = next.map { #", "nextPageToken": "\#($0)""# } ?? ""
        return .raw(200, #"{"jobs": [\#(jobs.joined(separator: ","))], "totalSize": "9"\#(token)}"#)
    }

    static let connections = HTTPResponse.raw(
        200,
        """
        {"connections": [
          {"connectionId": "c1", "installationId": "11", "account": "acme",
           "status": "GITHUB_ACTIONS_CONNECTION_STATUS_ACTIVE",
           "repositorySelection": "GITHUB_ACTIONS_REPOSITORY_SELECTION_ALL"},
          {"connectionId": "c2", "installationId": "12", "account": "octo",
           "status": "GITHUB_ACTIONS_CONNECTION_STATUS_ACTIVE"},
          {"connectionId": "c3", "installationId": "13", "account": "gone",
           "status": "GITHUB_ACTIONS_CONNECTION_STATUS_SUSPENDED"}
        ]}
        """
    )

    /// Each connection's repositories; acme's come in two pages.
    static func repositories(_ request: HTTPRequest) -> HTTPResponse? {
        switch (request.depotBody["connectionId"] as? String, request.depotBody["pageToken"]) {
            case ("c1", nil):
                .raw(
                    200,
                    #"{"repositories": [{"repository": "acme/app", "private": true}], "nextPageToken": "p2"}"#
                )
            case ("c1", _): .raw(200, #"{"repositories": [{"repository": "acme/web"}]}"#)
            case ("c2", _): .raw(200, #"{"repositories": [{"repository": "octo/lib"}]}"#)
            default: nil
        }
    }
}

extension HTTPRequest {
    var depotRepositories: [String]? {
        depotBody["repositories"] as? [String]
    }

    var depotJobStatuses: [String] {
        depotBody["statuses"] as? [String] ?? []
    }
}

@Suite("Depot service")
struct DepotServiceTests {
    func service(_ respond: @escaping @Sendable (HTTPRequest) -> HTTPResponse?) -> (
        DepotService, StubTransport
    ) {
        let stub = StubTransport { request, _ in respond(request) ?? .raw(404, "") }
        return (DepotService(token: "t", transport: stub, retryPolicy: .limitRetries(0)), stub)
    }

    func snapshot(
        _ query: StatusQuery = StatusQuery(),
        _ respond: @escaping @Sendable (HTTPRequest) -> HTTPResponse?
    ) async -> (Result<StatusSnapshot, RunnersError>, StubTransport) {
        let (service, stub) = service(respond)
        let monitor = RunsMonitor(service: service, now: { Fixtures.now })
        return (await monitor.snapshot(query), stub)
    }

    /// The scope: the app's connections and their repositories.
    static func scope(_ request: HTTPRequest) -> HTTPResponse? {
        switch request.depotMethod {
            case "ListGithubActionsConnections": DepotGitHubFixtures.connections
            case "ListGithubActionsRepositories": DepotGitHubFixtures.repositories(request)
            default: nil
        }
    }

    static func decode(_ json: String) throws -> DepotGitHubJob {
        try JSONCoding.decode(DepotGitHubJob.self, from: Data(json.utf8)).get()
    }

    @Test("maps statuses and conclusions, named as the proto names them")
    func statuses() {
        #expect(RunStatus(depotGitHub: "GITHUB_ACTIONS_JOB_STATUS_QUEUED") == .queued)
        #expect(RunStatus(depotGitHub: "GITHUB_ACTIONS_JOB_STATUS_WAITING") == .waiting)
        #expect(RunStatus(depotGitHub: "GITHUB_ACTIONS_JOB_STATUS_RUNNING") == .running)
        #expect(RunStatus(depotGitHub: "GITHUB_ACTIONS_JOB_STATUS_FINISHED") == .completed)
        #expect(RunStatus(depotGitHub: nil) == .unknown)
        #expect(RunStatus.active.compactMap(\.depotGitHubValue).count == 3)
        #expect(RunStatus.pending.depotGitHubValue == nil)
        #expect(Conclusion(depotGitHub: "GITHUB_ACTIONS_JOB_CONCLUSION_SUCCESS") == .success)
        #expect(Conclusion(depotGitHub: "GITHUB_ACTIONS_JOB_CONCLUSION_FAILURE") == .failure)
        #expect(Conclusion(depotGitHub: "GITHUB_ACTIONS_JOB_CONCLUSION_CANCELLED") == .cancelled)
        #expect(Conclusion(depotGitHub: "GITHUB_ACTIONS_JOB_CONCLUSION_SKIPPED") == .skipped)
        #expect(Conclusion(depotGitHub: "GITHUB_ACTIONS_JOB_CONCLUSION_NEUTRAL") == .neutral)
        #expect(Conclusion(depotGitHub: "GITHUB_ACTIONS_JOB_CONCLUSION_UNSPECIFIED") == nil)
        #expect(Conclusion(depotGitHub: nil) == nil)
        #expect(Conclusion(depotGitHub: "GITHUB_ACTIONS_JOB_CONCLUSION_NEW") == .unknown)
    }

    @Test("reads 64-bit integers as strings or numbers")
    func int64() throws {
        let decoded = try JSONCoding.decode([ProtoInt64].self, from: Data(#"["12", 7]"#.utf8))
            .get()
        #expect(decoded.map(\.value) == [12, 7])
        #expect(JSONCoding.decode(ProtoInt64.self, from: Data(#""x""#.utf8)).failure != nil)
    }

    @Test("sums a run up from its jobs: running while any runs, failed if any failed")
    func runFromJobs() throws {
        let done = DepotGitHubFixtures.job("1", status: "FINISHED", conclusion: "SUCCESS")
        let jobs = try [
            Self.decode(done),
            Self.decode(DepotGitHubFixtures.job("2", status: "QUEUED", started: nil)),
        ]
        #expect(DepotGitHubRun(id: "100", repository: "acme/app", jobs: jobs).run.status == .queued)
        let running = try jobs + [Self.decode(DepotGitHubFixtures.job("3"))]
        #expect(
            DepotGitHubRun(id: "100", repository: "acme/app", jobs: running).run.status == .running
        )

        let finished = try [
            Self.decode(DepotGitHubFixtures.job("1", status: "FINISHED", conclusion: "SUCCESS")),
            Self.decode(DepotGitHubFixtures.job("2", status: "FINISHED", conclusion: "SKIPPED")),
        ]
        let passed = DepotGitHubRun(id: "100", repository: "acme/app", jobs: finished)
        #expect(passed.run.status == .completed)
        #expect(passed.run.conclusion == .success)
        let failed = try DepotGitHubRun(
            id: "100",
            repository: "acme/app",
            jobs: finished + [
                Self.decode(
                    DepotGitHubFixtures.job("4", status: "FINISHED", conclusion: "CANCELLED")
                ),
                Self.decode(
                    DepotGitHubFixtures.job("5", status: "FINISHED", conclusion: "FAILURE")
                ),
            ]
        )
        #expect(failed.run.conclusion == .failure)

        // A re-run gives the job a new ID; the newest attempt is the one that counts.
        let rerun = try DepotGitHubRun(
            id: "100",
            repository: "acme/app",
            jobs: [
                Self.decode(
                    DepotGitHubFixtures.job(
                        "6",
                        name: "test",
                        status: "FINISHED",
                        conclusion: "FAILURE",
                        created: "2027-01-15T07:00:00Z"
                    )
                ),
                Self.decode(
                    DepotGitHubFixtures.job(
                        "7",
                        name: "test",
                        status: "FINISHED",
                        conclusion: "SUCCESS",
                        created: "2027-01-15T07:30:00Z"
                    )
                ),
            ]
        )
        #expect(rerun.jobs.map(\.jobId) == ["7"])
        #expect(rerun.run.conclusion == .success)
    }

    @Test("shows the unfinished runs of the connected repositories, with all their Depot jobs")
    func activeRuns() async throws {
        let (result, stub) = await snapshot { request in
            if let scope = Self.scope(request) { return scope }
            guard request.depotMethod == "ListGithubActionsJobs" else { return nil }
            switch request.depotBody["query"] as? String {
                case nil:
                    return DepotGitHubFixtures.jobs([
                        DepotGitHubFixtures.job("1", name: "build"),
                        DepotGitHubFixtures.job(
                            "2",
                            run: "200",
                            repo: "octo/lib",
                            status: "QUEUED",
                            started: nil
                        ),
                        DepotGitHubFixtures.job("3", run: "300", repo: "other/repo"),
                    ])
                case "100":
                    return DepotGitHubFixtures.jobs([
                        DepotGitHubFixtures.job("1", name: "build"),
                        DepotGitHubFixtures.job(
                            "0",
                            name: "lint",
                            status: "FINISHED",
                            conclusion: "SUCCESS",
                            created: "2027-01-15T07:57:00Z",
                            finished: "2027-01-15T07:59:00Z"
                        ),
                        // The query matches names too: a job of another run.
                        DepotGitHubFixtures.job("9", run: "555", name: "build 100"),
                    ])
                case "200":
                    return DepotGitHubFixtures.jobs([
                        DepotGitHubFixtures.job(
                            "2",
                            run: "200",
                            repo: "octo/lib",
                            status: "QUEUED",
                            started: nil
                        )
                    ])
                default: return nil
            }
        }
        let snapshot = try result.get()
        #expect(snapshot.provider.id == "depot")
        #expect(snapshot.owner == nil)
        #expect(snapshot.repositoryCount == 3)
        #expect(snapshot.runs.map(\.run.id) == ["100", "200"])

        let app = try #require(snapshot.runs.first)
        #expect(app.repository.fullName == "acme/app")
        #expect(app.repository.isPrivate)
        #expect(app.run.name == "CI")
        #expect(app.run.status == .running)
        #expect(app.run.conclusion == nil)
        #expect(app.run.webURL.absoluteString == "https://github.com/acme/app/actions/runs/100")
        #expect(app.run.createdAt == JSONCoding.parseDate("2027-01-15T07:57:00Z"))
        #expect(app.run.completedAt == nil)

        // Oldest first.
        let jobs = try #require(app.jobs)
        #expect(jobs.map(\.name) == ["lint", "build"])
        #expect(jobs.map(\.status) == [.completed, .running])
        #expect(jobs[0].conclusion == .success)
        let build = jobs[1]
        #expect(build.labels == ["depot-ubuntu-24.04-4"])
        #expect(build.runnerHost == .depot)
        #expect(build.runner == "depot-ubuntu-24.04-4, 4 CPUs, 16 GB, 12s in queue")
        #expect(build.startedAt != nil)
        #expect(build.conclusion == nil)
        #expect(
            build.webURL?.absoluteString == "https://github.com/acme/app/actions/runs/100/job/1"
        )

        let lib = try #require(snapshot.runs.last)
        #expect(lib.run.status == .queued)
        #expect(lib.jobs?.first?.runner == "depot-ubuntu-24.04-4, 4 CPUs, 16 GB")

        let methods = stub.requests.map(\.depotMethod)
        #expect(methods.filter { $0 == "ListGithubActionsConnections" }.count == 1)
        // acme's two pages and octo's one; the suspended connection isn't read.
        #expect(
            stub.requests.filter { $0.depotMethod == "ListGithubActionsRepositories" }
                .compactMap { $0.depotBody["connectionId"] as? String }.sorted()
                == ["c1", "c1", "c2"]
        )
        let listings = stub.requests.filter { $0.depotMethod == "ListGithubActionsJobs" }
        let unfinished = try #require(listings.first { $0.depotBody["query"] == nil })
        #expect(
            Set(unfinished.depotJobStatuses) == [
                "GITHUB_ACTIONS_JOB_STATUS_QUEUED", "GITHUB_ACTIONS_JOB_STATUS_WAITING",
                "GITHUB_ACTIONS_JOB_STATUS_RUNNING",
            ]
        )
        #expect(unfinished.depotRepositories == nil)
        #expect(unfinished.depotBody["pageSize"] as? Int == 250)
        // other/repo isn't in the scope, so its run isn't read.
        #expect(
            Set(listings.compactMap { $0.depotBody["query"] as? String }) == ["100", "200"]
        )
        #expect(
            listings.filter { $0.depotBody["query"] as? String == "100" }.first?.depotRepositories
                == ["acme/app"]
        )

        let request = try #require(stub.requests.first)
        #expect(request.method == "POST")
        #expect(
            request.url.absoluteString
                == "https://api.depot.dev/depot.core.v1.GithubActionsService/ListGithubActionsConnections"
        )
        #expect(request.headers["Authorization"] == "Bearer t")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Connect-Protocol-Version"] == "1")
    }

    @Test("keeps an owner to the repositories of the app's installation on it")
    func owner() async throws {
        let query = StatusQuery(target: .owner("OCTO"), includeJobs: false)
        let (result, stub) = await snapshot(query) { request in
            if let scope = Self.scope(request) { return scope }
            guard request.depotMethod == "ListGithubActionsJobs" else { return nil }
            return DepotGitHubFixtures.jobs([
                DepotGitHubFixtures.job("2", run: "200", repo: "octo/lib")
            ])
        }
        let found = try result.get()
        #expect(found.owner?.login == "octo")
        #expect(found.repositoryCount == 1)
        #expect(found.runs.map(\.run.id) == ["200"])
        #expect(found.runs.first?.jobs == nil)
        let listings = stub.requests.filter { $0.depotMethod == "ListGithubActionsJobs" }
        #expect(listings.count == 1)
        #expect(listings.first?.depotRepositories == ["octo/lib"])

        let (missing, _) = await snapshot(StatusQuery(target: .owner("nobody"))) {
            Self.scope($0)
        }
        #expect(
            missing.failure
                == .notFound("the Depot GitHub App is not installed on nobody; it is on acme, octo")
        )
    }

    @Test("lists the repositories named with --repo, paging by token")
    func repositories() async throws {
        let query = StatusQuery(
            target: .repositories(["acme/app", "acme/web"]),
            includeJobs: false
        )
        let (result, stub) = await snapshot(query) { request in
            guard request.depotMethod == "ListGithubActionsJobs" else { return nil }
            return request.depotBody["pageToken"] == nil
                ? DepotGitHubFixtures.jobs([DepotGitHubFixtures.job("1")], next: "p2")
                : DepotGitHubFixtures.jobs([
                    DepotGitHubFixtures.job("5", run: "500", repo: "acme/web")
                ])
        }
        let snapshot = try result.get()
        #expect(snapshot.runs.map(\.repository.fullName) == ["acme/app", "acme/web"])
        #expect(stub.requests.map { $0.depotBody["pageToken"] as? String } == [nil, "p2"])
        #expect(stub.requests.allSatisfy { $0.depotRepositories == ["acme/app", "acme/web"] })
    }

    @Test("asks for nothing when no status asked for is one a Depot job has")
    func noJobStatus() async throws {
        let query = StatusQuery(target: .repositories(["acme/app"]), statuses: [.pending])
        let (result, stub) = await snapshot(query) { _ in nil }
        #expect(try result.get().runs.isEmpty)
        #expect(stub.requests.isEmpty)
    }

    @Test(
        "reads Connect errors: a rejected token says which one Depot wants",
        arguments: [
            (401, "unauthenticated", "invalid token"),
            (403, "permission_denied", "not allowed"),
            (404, "not_found", "no such job"),
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

    @Test("reads a run again once it drops out, with how its jobs ended")
    func latest() async throws {
        let (service, stub) = service { request in
            guard request.depotMethod == "ListGithubActionsJobs" else { return nil }
            return request.depotBody["query"] as? String == "100"
                ? DepotGitHubFixtures.jobs([
                    DepotGitHubFixtures.job(
                        "1",
                        status: "FINISHED",
                        conclusion: "FAILURE",
                        finished: "2027-01-15T08:03:00Z"
                    ),
                    DepotGitHubFixtures.job(
                        "2",
                        status: "FINISHED",
                        conclusion: "SUCCESS",
                        finished: "2027-01-15T08:04:00Z"
                    ),
                ])
                : DepotGitHubFixtures.jobs([])
        }
        let running = try DepotGitHubRun(
            id: "100",
            repository: "acme/app",
            jobs: [Self.decode(DepotGitHubFixtures.job("1"))]
        )
        let repository = Repository(gitHubFullName: "acme/app")
        let latest = try await service.latest(
            running.activeRun(in: repository, includeJobs: true),
            query: StatusQuery()
        )
        .get()
        #expect(latest.run.status == .completed)
        #expect(latest.run.conclusion == .failure)
        #expect(latest.run.completedAt == JSONCoding.parseDate("2027-01-15T08:04:00Z"))
        #expect(latest.jobs?.map(\.conclusion) == [.failure, .success])
        #expect(stub.requests.first?.depotRepositories == ["acme/app"])
        #expect(stub.requests.first?.depotJobStatuses == [])

        let gone = DepotGitHubRun(id: "404", repository: "acme/app", jobs: running.jobs)
        let missing = await service.latest(
            gone.activeRun(in: repository, includeJobs: false),
            query: StatusQuery()
        )
        #expect(missing.failure == .notFound("Depot jobs of run 404 in acme/app"))
    }
}
