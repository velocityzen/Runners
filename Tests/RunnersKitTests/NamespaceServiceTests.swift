import FPRetry
import Foundation
import Testing

@testable import RunnersKit

/// Shapes from buf.build/namespace/cloud's `github/v1beta/jobs.proto` and `profiles.proto`, in
/// proto3 JSON: 64-bit integers as strings, fields at their default left out.
enum NamespaceFixtures {
    static func job(
        _ id: String,
        run: String = "100",
        repo: String = "acme/app",
        name: String? = nil,
        profile: String? = "linux-4",
        runner: Bool = true,
        started: String? = "2027-01-15T07:58:13Z",
        completed: String? = nil,
        conclusion: String? = nil,
        created: String = "2027-01-15T07:58:00Z"
    ) -> String {
        let fields: [String?] = [
            #""tenantId": "tenant1""#,
            #""jobId": "\#(id)""#,
            #""repository": "\#(repo)""#,
            #""runId": "\#(run)""#,
            #""workflowName": "CI""#,
            #""jobName": "\#(name ?? "job \(id)")""#,
            conclusion.map { #""conclusion": "\#($0)""# },
            #""jobUrl": "https://github.com/\#(repo)/actions/runs/\#(run)/job/\#(id)""#,
            #""senderLogin": "octocat""#,
            #""ref": "refs/heads/main""#,
            #""createdAt": "\#(created)""#,
            #""queuedAt": "2027-01-15T07:58:10Z""#,
            started.map { #""startedAt": "\#($0)""# },
            completed.map { #""completedAt": "\#($0)""# },
            runner && started != nil
                ? #""runner": {"runnerId": "77", "runnerName": "nsc-runner-\#(id)", "instanceId": "inst\#(id)", "containerName": "c1"}"#
                : nil,
            profile.map { #""profile": {"tag": "\#($0)"}"# },
        ]
        return "{" + fields.compactMap(\.self).joined(separator: ", ") + "}"
    }

    static func jobs(_ jobs: [String], cursor: String? = nil) -> HTTPResponse {
        let next = cursor.map { #", "paginationCursor": "\#($0)""# } ?? ""
        return .raw(200, #"{"jobs": [\#(jobs.joined(separator: ","))]\#(next)}"#)
    }

    static let profiles = HTTPResponse.raw(
        200,
        """
        {"profiles": [
          {"profileId": "p1", "version": "3",
           "spec": {"tag": "linux-4", "os": "ubuntu-24.04",
                    "instanceShape": {"virtualCpu": 4, "memoryMegabytes": 8192,
                                      "machineArch": "arm64", "os": "linux"}}},
          {"profileId": "p2", "spec": {"tag": "mac"}}
        ]}
        """
    )
}

extension HTTPRequest {
    var namespaceRepositories: [String]? {
        (depotBody["repository"] as? [String: Any])?["values"] as? [String]
    }
}

@Suite("Namespace service")
struct NamespaceServiceTests {
    func service(_ respond: @escaping @Sendable (HTTPRequest) -> HTTPResponse?) -> (
        NamespaceService, StubTransport
    ) {
        let stub = StubTransport { request, _ in respond(request) ?? .raw(404, "") }
        return (NamespaceService(token: "t", transport: stub, retryPolicy: .limitRetries(0)), stub)
    }

    func snapshot(
        _ query: StatusQuery = StatusQuery(),
        _ respond: @escaping @Sendable (HTTPRequest) -> HTTPResponse?
    ) async -> (Result<StatusSnapshot, RunnersError>, StubTransport) {
        let (service, stub) = service(respond)
        let monitor = RunsMonitor(service: service, now: { Fixtures.now })
        return (await monitor.snapshot(query), stub)
    }

    /// The latest jobs, which make the scope: a ListJobs with no filter.
    static func recent(_ request: HTTPRequest) -> HTTPResponse? {
        guard request.depotMethod == "ListJobs", request.depotBody["hasNotFinished"] == nil,
            request.depotBody["hasNotStarted"] == nil, request.depotBody["timeRange"] == nil
        else { return nil }
        return NamespaceFixtures.jobs([
            NamespaceFixtures.job("1"),
            NamespaceFixtures.job(
                "8",
                run: "80",
                repo: "acme/web",
                completed: "2027-01-15T07:00:00Z"
            ),
            NamespaceFixtures.job(
                "9",
                run: "90",
                repo: "octo/lib",
                completed: "2027-01-15T07:00:00Z"
            ),
        ])
    }

    static func decode(_ json: String) throws -> NamespaceJob {
        try JSONCoding.decode(NamespaceJob.self, from: Data(json.utf8)).get()
    }

    @Test("reads a job's status from its times, and its conclusion as GitHub's")
    func statuses() throws {
        let queued = try Self.decode(NamespaceFixtures.job("1", started: nil))
        #expect(queued.status == .queued)
        #expect(queued.job(shape: nil).runner == nil)
        #expect(queued.job(shape: nil).labels == ["namespace-profile-linux-4"])
        #expect(queued.job(shape: nil).runnerHost == .namespace)
        #expect(try Self.decode(NamespaceFixtures.job("2")).status == .running)
        let done = try Self.decode(
            NamespaceFixtures.job("3", completed: "2027-01-15T08:00:00Z", conclusion: "failure")
        )
        #expect(done.status == .completed)
        #expect(done.job(shape: nil).conclusion == .failure)
        #expect(done.jobId.value == 3)
        let noProfile = try Self.decode(NamespaceFixtures.job("4", profile: nil))
        #expect(noProfile.job(shape: nil).labels.isEmpty)
    }

    @Test("describes a profile's machine")
    func shapes() throws {
        let profiles = try JSONCoding.decode(
            NamespaceProfiles.self,
            from: NamespaceFixtures.profiles.body
        )
        .get()
        let shapes = profiles.shapes
        #expect(shapes.keys.sorted() == ["linux-4"])
        #expect(shapes["linux-4"]?.description == "4 CPUs, 8 GB, linux arm64")
        let small = NamespaceShape(virtualCpu: 2, memoryMegabytes: 1536, machineArch: nil, os: nil)
        #expect(small.description == "2 CPUs, 1.5 GB")
    }

    @Test("shows the unfinished runs of the repositories its latest jobs were for")
    func activeRuns() async throws {
        let (result, stub) = await snapshot { request in
            if let recent = Self.recent(request) { return recent }
            switch request.depotMethod {
                case "ListJobs":
                    return request.depotBody["paginationCursor"] == nil
                        ? NamespaceFixtures.jobs(
                            [
                                NamespaceFixtures.job("1", name: "build"),
                                NamespaceFixtures.job("2", name: "test", runner: false),
                            ],
                            cursor: "Y3Vyc29y"
                        )
                        : NamespaceFixtures.jobs([
                            NamespaceFixtures.job("5", run: "500", repo: "acme/web", started: nil),
                            NamespaceFixtures.job("6", run: "600", repo: "other/repo"),
                        ])
                case "DescribeJob" where request.depotBody["jobId"] as? String == "2":
                    return .raw(200, #"{"job": \#(NamespaceFixtures.job("2", name: "test"))}"#)
                case "ListProfiles": return NamespaceFixtures.profiles
                default: return nil
            }
        }
        let snapshot = try result.get()
        #expect(snapshot.provider.id == "namespace")
        #expect(snapshot.owner == nil)
        #expect(snapshot.repositoryCount == 3)
        #expect(snapshot.runs.map(\.run.id) == ["100", "500"])

        let app = try #require(snapshot.runs.first)
        #expect(app.repository.fullName == "acme/app")
        #expect(app.run.name == "CI")
        #expect(app.run.status == .running)
        #expect(app.run.branch == "main")
        #expect(app.run.actor == "octocat")
        #expect(app.run.webURL.absoluteString == "https://github.com/acme/app/actions/runs/100")
        #expect(app.run.startedAt == JSONCoding.parseDate("2027-01-15T07:58:13Z"))
        let jobs = try #require(app.jobs)
        #expect(jobs.map(\.name) == ["build", "test"])
        #expect(jobs.map(\.status) == [.running, .running])
        #expect(
            jobs.map(\.runner) == [
                "nsc-runner-1, instance inst1, 4 CPUs, 8 GB, linux arm64, 3s in queue",
                "nsc-runner-2, instance inst2, 4 CPUs, 8 GB, linux arm64, 3s in queue",
            ]
        )
        #expect(jobs[0].runnerHost == .namespace)
        #expect(
            jobs[0].webURL?.absoluteString == "https://github.com/acme/app/actions/runs/100/job/1"
        )

        let web = try #require(snapshot.runs.last)
        #expect(web.run.status == .queued)
        #expect(web.jobs?.first?.labels == ["namespace-profile-linux-4"])

        let listings = stub.requests.filter {
            $0.depotMethod == "ListJobs" && $0.depotBody["hasNotFinished"] as? Bool == true
        }
        #expect(listings.map { $0.depotBody["paginationCursor"] as? String } == [nil, "Y3Vyc29y"])
        #expect(listings.allSatisfy { $0.depotBody["maxEntries"] as? String == "100" })
        #expect(listings.allSatisfy { $0.namespaceRepositories == nil })
        // Only the running job without a runner is read again.
        #expect(
            stub.requests.filter { $0.depotMethod == "DescribeJob" }.map {
                $0.depotBody["jobId"] as? String
            } == ["2"]
        )
        #expect(stub.requests.filter { $0.depotMethod == "ListProfiles" }.count == 1)

        let request = try #require(stub.requests.first)
        #expect(request.method == "POST")
        #expect(
            request.url.absoluteString
                == "https://global.namespaceapis.com/namespace.cloud.github.v1beta.JobsService/ListJobs"
        )
        #expect(request.headers["Authorization"] == "Bearer t")
        #expect(request.headers["Connect-Protocol-Version"] == "1")
    }

    @Test("keeps an owner's repositories, and asks for queued jobs only when that's all it wants")
    func owner() async throws {
        let query = StatusQuery(target: .owner("ACME"), statuses: [.queued], includeJobs: false)
        let (result, stub) = await snapshot(query) { request in
            if let recent = Self.recent(request) { return recent }
            guard request.depotMethod == "ListJobs" else { return nil }
            return NamespaceFixtures.jobs([
                NamespaceFixtures.job("5", run: "500", repo: "acme/web", started: nil)
            ])
        }
        let found = try result.get()
        #expect(found.owner?.login == "ACME")
        #expect(found.repositoryCount == 2)
        #expect(found.runs.map(\.run.id) == ["500"])
        #expect(found.runs.first?.jobs == nil)
        let listing = try #require(
            stub.requests.first { $0.depotBody["hasNotStarted"] as? Bool == true }
        )
        #expect(listing.depotBody["hasNotFinished"] == nil)
        #expect(listing.namespaceRepositories == ["acme/app", "acme/web"])
        #expect(
            (listing.depotBody["repository"] as? [String: Any])?["op"] as? String == "IS_ANY_OF"
        )
        #expect(!stub.requests.contains { $0.depotMethod == "ListProfiles" })
    }

    @Test("asks for nothing when no status asked for is one a Namespace job has")
    func noJobStatus() async throws {
        let query = StatusQuery(target: .repositories(["acme/app"]), statuses: [.waiting])
        let (result, stub) = await snapshot(query) { _ in nil }
        #expect(try result.get().runs.isEmpty)
        #expect(stub.requests.isEmpty)
    }

    @Test(
        "reads Connect errors: a token it can't read is a rejected token",
        arguments: [
            (401, "unauthenticated", "token expired"),
            (400, "invalid_argument", "invalid token format: invalid ID format (rid=abc)"),
            (400, "invalid_argument", "bad filter"),
            (403, "permission_denied", "missing grant"),
            (503, "unavailable", "try again"),
        ]
    )
    func errors(_ status: Int, _ code: String, _ message: String) async {
        let (result, stub) = await snapshot(StatusQuery(target: .repositories(["acme/app"]))) {
            _ in .raw(status, #"{"code": "\#(code)", "message": "\#(message)"}"#)
        }
        let expected: RunnersError =
            switch (code, message.hasPrefix("invalid token")) {
                case ("unauthenticated", _), ("invalid_argument", true):
                    .unauthorized("\(message); \(NamespaceAPI.tokenHelp)")
                case ("permission_denied", _): .forbidden(message)
                case ("invalid_argument", false): .unexpectedStatus(400, message: message)
                default: .server(status: status, message: message)
            }
        #expect(result.failure == expected)
        #expect(stub.requests.count == 1)
    }

    @Test("reads a run again once it drops out, from its repository's jobs since it began")
    func latest() async throws {
        let (service, stub) = service { request in
            guard request.depotMethod == "ListJobs" else { return nil }
            return NamespaceFixtures.jobs([
                NamespaceFixtures.job(
                    "1",
                    name: "build",
                    completed: "2027-01-15T08:03:00Z",
                    conclusion: "success"
                ),
                NamespaceFixtures.job(
                    "3",
                    name: "deploy",
                    completed: "2027-01-15T08:05:00Z",
                    conclusion: "cancelled",
                    created: "2027-01-15T08:02:00Z"
                ),
                NamespaceFixtures.job("7", run: "700"),
            ])
        }
        let running = try NamespaceRun(
            id: "100",
            repository: "acme/app",
            jobs: [Self.decode(NamespaceFixtures.job("1", name: "build"))]
        )
        let latest = try await service.latest(
            running.activeRun(
                in: Repository(gitHubFullName: "acme/app"),
                shapes: [:],
                includeJobs: false
            ),
            query: StatusQuery()
        )
        .get()
        #expect(latest.run.status == .completed)
        #expect(latest.run.conclusion == .cancelled)
        #expect(latest.run.completedAt == JSONCoding.parseDate("2027-01-15T08:05:00Z"))
        #expect(latest.jobs?.map(\.id) == ["1", "3"])
        let request = try #require(stub.requests.first)
        #expect(request.namespaceRepositories == ["acme/app"])
        #expect(
            (request.depotBody["timeRange"] as? [String: Any])?["after"] as? String
                == "2027-01-15T07:57:59Z"
        )
    }

    @Test("falls back to the nsc CLI's development token")
    func devToken() {
        #expect(NamespaceProvider.devToken.command == "nsc")
        #expect(NamespaceProvider.devToken.arguments == ["auth", "generate-dev-token"])
    }
}
