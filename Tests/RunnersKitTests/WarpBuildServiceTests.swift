import FPRetry
import Foundation
import Testing

@testable import RunnersKit

/// Shapes from WarpBuild's API reference for `GET /runners` and `GET /runner_instance`.
enum WarpBuildFixtures {
    static func instance(
        _ id: String,
        status: String = "running",
        set: String? = "rs1",
        stock: String? = nil,
        label: String = "warp-linux-x64-4x",
        repo: String = "app",
        started: String? = "2027-01-15T07:58:12Z",
        ended: String? = nil,
        sku: String = #"{"id": "sku1", "cores": 4, "memory": 16, "arch": "x64"}"#
    ) -> String {
        let fields: [String?] = [
            #""id": "\#(id)""#,
            #""status": "\#(status)""#,
            #""labels": ["\#(label)"]"#,
            set.map { #""runner_set_id": "\#($0)""# },
            #""last_job_processed_id": "job-\#(id)""#,
            """
            "last_job_processed_meta": {"vcs_org": "acme", "vcs_repo": "\(repo)",
             "vcs_workflow_name": "CI", "vcs_job_name": "build \(id)",
             "vcs_ref": "refs/heads/main", "vcs_head_ref": "",
             "vcs_start_time": "2027-01-15T07:58:12Z"\(ended.map { #", "vcs_end_time": "\#($0)""# } ?? "")}
            """,
            #""configuration": {"image": "ubuntu-2404", "sku": \#(sku)\#(stock.map { #", "stock_runner_set_id": "\#($0)""# } ?? "")}"#,
            #""created_at": "2027-01-15T07:50:00Z""#,
            #""allocation_requested_at": "2027-01-15T07:58:00Z""#,
            started.map { #""running_started_at": "\#($0)""# },
        ]
        return "{" + fields.compactMap(\.self).joined(separator: ", ") + "}"
    }

    static func page(
        _ instances: [String],
        page: Int = 1,
        next: Int = 0,
        totalPages: Int = 1
    ) -> HTTPResponse {
        .raw(
            200,
            #"{"page": \#(page), "per_page": 100, "next_page": \#(next), "total_items": \#(instances.count), "total_pages": \#(totalPages), "runner_instances": [\#(instances.joined(separator: ","))]}"#
        )
    }

    static let runnerSets = HTTPResponse.raw(
        200,
        """
        [{"id": "rs1", "name": "linux", "active": true, "labels": ["warp-linux-x64-4x"],
          "configuration": {"image": "ubuntu-2404", "sku": "warp-ubuntu-2404-x64-4x"},
          "organization_id": "org1"},
         {"id": "rs2", "name": "old", "active": false, "labels": ["warp-old"]}]
        """
    )
}

@Suite("WarpBuild service")
struct WarpBuildServiceTests {
    func service(_ respond: @escaping @Sendable (HTTPRequest) -> HTTPResponse?) -> (
        WarpBuildService, StubTransport
    ) {
        let stub = StubTransport { request, _ in respond(request) ?? .raw(404, "") }
        return (
            WarpBuildService(key: "wkey-t", transport: stub, retryPolicy: .limitRetries(0)), stub
        )
    }

    func snapshot(
        _ query: StatusQuery = StatusQuery(),
        _ respond: @escaping @Sendable (HTTPRequest) -> HTTPResponse?
    ) async -> (Result<StatusSnapshot, RunnersError>, StubTransport) {
        let (service, stub) = service(respond)
        let monitor = RunsMonitor(service: service, now: { Fixtures.now })
        return (await monitor.snapshot(query), stub)
    }

    /// The runner sets, and the latest instances, among them a stock runner's.
    static func scope(_ request: HTTPRequest) -> HTTPResponse? {
        switch request.url.path() {
            case "/api/v1/runners": return WarpBuildFixtures.runnerSets
            case "/api/v1/runner_instance" where request.queryValues("status").isEmpty:
                return WarpBuildFixtures.page([
                    WarpBuildFixtures.instance("i0", status: "purged"),
                    WarpBuildFixtures.instance(
                        "i9",
                        status: "completed",
                        set: nil,
                        stock: "stock-ubuntu",
                        label: "warp-ubuntu-latest-x64-2x"
                    ),
                ])
            default: return nil
        }
    }

    @Test("reads an instance's status as its job's")
    func statuses() {
        #expect(RunStatus(warpBuild: "allocating") == .queued)
        #expect(RunStatus(warpBuild: "allocated") == .queued)
        #expect(RunStatus(warpBuild: "running") == .running)
        for done in ["polling", "suspended", "completed", "purging", "purged"] {
            #expect(RunStatus(warpBuild: done) == .completed)
        }
        #expect(RunStatus(warpBuild: "new") == .unknown)
        #expect(
            RunStatus.active.flatMap(\.warpBuildValues) == ["running", "allocating", "allocated"]
        )
    }

    @Test("shows each busy or starting instance as a run of one job, by runner set")
    func activeRuns() async throws {
        let (result, stub) = await snapshot { request in
            if let scope = Self.scope(request) { return scope }
            guard request.url.path() == "/api/v1/runner_instance" else { return nil }
            return request.query("page") == "1"
                ? WarpBuildFixtures.page(
                    [
                        WarpBuildFixtures.instance("i1"),
                        WarpBuildFixtures.instance(
                            "i2",
                            status: "allocating",
                            set: nil,
                            stock: "stock-ubuntu",
                            label: "warp-ubuntu-latest-x64-2x",
                            repo: "acme/web",
                            started: nil,
                            sku: #"{"display_name": "2 vCPU, 8 GB", "cores": 2}"#
                        ),
                    ],
                    next: 2,
                    totalPages: 2
                )
                : WarpBuildFixtures.page(
                    [WarpBuildFixtures.instance("i3", set: "rs-other", label: "warp-other")],
                    page: 2,
                    totalPages: 2
                )
        }
        let found = try result.get()
        #expect(found.provider.id == "warpbuild")
        #expect(found.owner == nil)
        // linux and old from the listing, the stock runner from the latest instances.
        #expect(found.repositoryCount == 3)
        #expect(found.runs.map(\.run.id) == ["i1", "i2"])
        #expect(found.summary == "2 active runs in 2 of 3 runner sets")

        let busy = try #require(found.runs.first)
        #expect(busy.repository.name == "linux")
        #expect(busy.repository.id == "rs1")
        #expect(busy.run.name == "CI")
        #expect(busy.run.title == "acme/app")
        #expect(busy.run.status == .running)
        #expect(busy.run.conclusion == nil)
        #expect(busy.run.branch == "main")
        #expect(busy.run.webURL.absoluteString == "https://github.com/acme/app/actions")
        #expect(busy.run.createdAt == JSONCoding.parseDate("2027-01-15T07:58:00Z"))
        let job = try #require(busy.jobs?.first)
        #expect(job.id == "job-i1")
        #expect(job.name == "build i1")
        #expect(job.labels == ["warp-linux-x64-4x"])
        #expect(job.runnerHost == .warpBuild)
        #expect(job.runner == "4 CPUs, 16 GB, x64, 12s in queue")
        #expect(job.startedAt == JSONCoding.parseDate("2027-01-15T07:58:12Z"))

        let starting = try #require(found.runs.last)
        #expect(starting.repository.name == "warp-ubuntu-latest-x64-2x")
        #expect(starting.run.status == .queued)
        #expect(starting.run.title == "acme/web")
        #expect(starting.jobs?.first?.runner == "2 vCPU, 8 GB")

        let listings = stub.requests.filter { !$0.queryValues("status").isEmpty }
        #expect(listings.map { $0.query("page") } == ["1", "2"])
        #expect(
            listings.allSatisfy {
                $0.queryValues("status") == ["running", "allocating", "allocated"]
                    && $0.query("include_cloud_runners") == "true"
                    && $0.query("per_page") == "100"
            }
        )
        let request = try #require(stub.requests.first)
        #expect(request.headers["Authorization"] == "Bearer wkey-t")
        #expect(request.url.host() == "api.warpbuild.com")
    }

    @Test("names runner sets with --repo by ID, name or label")
    func repositories() async throws {
        let query = StatusQuery(
            target: .repositories(["linux", "warp-ubuntu-latest-x64-2x", "RS1"]),
            includeJobs: false
        )
        let (result, _) = await snapshot(query) { request in
            if let scope = Self.scope(request) { return scope }
            return WarpBuildFixtures.page([WarpBuildFixtures.instance("i1")])
        }
        let found = try result.get()
        #expect(found.repositoryCount == 2)
        #expect(found.runs.map(\.run.id) == ["i1"])
        #expect(found.runs.first?.jobs == nil)

        let (missing, _) = await snapshot(StatusQuery(target: .repositories(["nope"]))) {
            Self.scope($0)
        }
        #expect(missing.failure == .notFound("WarpBuild runner set nope"))
    }

    @Test("has no owners, and asks for nothing when no status asked for is an instance's")
    func nothingToAsk() async throws {
        let (owned, ownedStub) = await snapshot(StatusQuery(target: .owner("acme"))) { _ in nil }
        guard case .failure(.configuration(let reason)) = owned else {
            Issue.record("expected a configuration failure")
            return
        }
        #expect(reason.contains("WarpBuild has no owners"))
        #expect(ownedStub.requests.isEmpty)

        let query = StatusQuery(target: .repositories(["linux"]), statuses: [.pending])
        let (result, stub) = await snapshot(query) { Self.scope($0) }
        #expect(try result.get().runs.isEmpty)
        #expect(stub.requests.allSatisfy { $0.queryValues("status").isEmpty })
    }

    @Test(
        "reads WarpBuild's errors: a rejected key says which one it wants",
        arguments: [
            (401, "Failed to verify token: Invalid API key."),
            (403, "Key lacks the CI scope."),
            (500, "Internal error."),
        ]
    )
    func errors(_ status: Int, _ description: String) async {
        let (result, _) = await snapshot(StatusQuery(target: .repositories(["linux"]))) { _ in
            .raw(
                status,
                #"{"code": "UNA", "message": "unauthorized access", "sub_code": "UNA_001", "description": "\#(description)"}"#
            )
        }
        let expected: RunnersError =
            switch status {
                case 401: .unauthorized("\(description.dropLast()); \(WarpBuildAPI.keyHelp)")
                case 403: .forbidden(String(description.dropLast()))
                default: .server(status: status, message: "unauthorized access")
            }
        #expect(result.failure == expected)
    }

    @Test("reads an instance again once it drops out, with no conclusion to give")
    func latest() async throws {
        let (service, stub) = service { request in
            guard request.url.path() == "/api/v1/runner_instance/i1" else { return nil }
            return .raw(
                200,
                WarpBuildFixtures.instance("i1", status: "polling", ended: "2027-01-15T08:04:00Z")
            )
        }
        let running = try JSONCoding.decode(
            WarpBuildInstance.self,
            from: Data(WarpBuildFixtures.instance("i1").utf8)
        )
        .get()
        let repository = WarpBuildGroup.repository(id: "rs1", name: "linux")
        let latest = try await service.latest(
            running.activeRun(in: repository, includeJobs: true),
            query: StatusQuery()
        )
        .get()
        #expect(stub.requests.count == 1)
        #expect(latest.repository == repository)
        #expect(latest.run.status == .completed)
        #expect(latest.run.conclusion == nil)
        #expect(latest.run.completedAt == JSONCoding.parseDate("2027-01-15T08:04:00Z"))
        #expect(latest.jobs?.first?.status == .completed)
    }

    @Test("pages while the next page is after this one and within the total")
    func paging() throws {
        func page(_ json: String) throws -> WarpBuildInstancesPage {
            try JSONCoding.decode(WarpBuildInstancesPage.self, from: Data(json.utf8)).get()
        }
        let one = #"[{"id": "i1"}]"#
        #expect(
            try page(#"{"page": 1, "next_page": 2, "total_pages": 3, "runner_instances": \#(one)}"#)
                .next == 2
        )
        #expect(
            try page(#"{"page": 3, "next_page": 0, "total_pages": 3, "runner_instances": \#(one)}"#)
                .next == nil
        )
        #expect(
            try page(#"{"page": 1, "next_page": 2, "total_pages": 1, "runner_instances": \#(one)}"#)
                .next == nil
        )
        #expect(try page(#"{"page": 1, "next_page": 2, "runner_instances": []}"#).next == nil)
    }
}
