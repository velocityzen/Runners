import FPRetry
import Foundation
import Synchronization
import Testing

@testable import RunnersKit

@Suite("AWS CodeBuild service")
struct AWSServiceTests {
    var codeBuild: FakeCodeBuild {
        var codeBuild = FakeCodeBuild()
        codeBuild.projects = [
            AWSFixtures.project("web-runner"),
            AWSFixtures.project("api-runner"),
            AWSFixtures.project("nightly", runner: false),
        ]
        codeBuild.builds["api-runner"] = [
            AWSFixtures.build("api-runner", 12, phase: "QUEUED", minutesAgo: 1),
            AWSFixtures.build("api-runner", 11, phase: "BUILD", minutesAgo: 6),
            AWSFixtures.build(
                "api-runner",
                10,
                phase: "COMPLETED",
                status: "SUCCEEDED",
                minutesAgo: 20
            ),
        ]
        codeBuild.builds["web-runner"] = [
            AWSFixtures.build("web-runner", 3, phase: "COMPLETED", status: "FAILED", minutesAgo: 30)
        ]
        codeBuild.builds["nightly"] = [AWSFixtures.build("nightly", 99, phase: "BUILD")]
        return codeBuild
    }

    func makeService(
        _ transport: some HTTPTransport,
        retryPolicy: RetryPolicy = .limitRetries(0),
        now: @escaping @Sendable () -> Date = { Fixtures.now }
    ) -> AWSService {
        AWSService(
            credentials: AWSFixtures.credentials,
            endpoint: AWSFixtures.endpoint,
            transport: transport,
            retryPolicy: retryPolicy,
            now: now
        )
    }

    func snapshot(
        _ codeBuild: FakeCodeBuild,
        _ query: StatusQuery = StatusQuery()
    ) async -> (Result<StatusSnapshot, RunnersError>, StubTransport) {
        let stub = codeBuild.transport()
        let monitor = RunsMonitor(service: makeService(stub), now: { Fixtures.now })
        return (await monitor.snapshot(query), stub)
    }

    @Test("watches the region's runner projects, and finds their unfinished builds with jobs")
    func runnerProjects() async throws {
        let (result, _) = await snapshot(codeBuild)
        let snapshot = try result.get()
        #expect(snapshot.provider.id == "aws")
        #expect(snapshot.owner == nil)
        #expect(snapshot.repositoryCount == 3)
        #expect(snapshot.runs.map(\.repository.fullName) == ["api-runner", "api-runner"])
        #expect(Set(snapshot.runs.map(\.run.number)) == [11, 12])
        #expect(snapshot.runs.allSatisfy { $0.jobs?.count == 1 })
        #expect(Set(snapshot.runs.map(\.run.status)) == [.queued, .running])
    }

    @Test("watches the projects named, runner projects or not, and only the statuses asked for")
    func named() async throws {
        let query = StatusQuery(
            target: .repositories(["nightly", "api-runner"]),
            statuses: [.running],
            includeJobs: false
        )
        let (result, _) = await snapshot(codeBuild, query)
        let snapshot = try result.get()
        #expect(snapshot.repositoryCount == 2)
        #expect(Set(snapshot.runs.map(\.run.id)) == ["nightly:uuid-99", "api-runner:uuid-11"])
        #expect(snapshot.runs.allSatisfy { $0.jobs == nil })
    }

    @Test("fails for a project that doesn't exist, and for an owner")
    func missing() async {
        let (missing, _) = await snapshot(codeBuild, StatusQuery(target: .repositories(["nope"])))
        #expect(missing.error == .notFound("CodeBuild project nope in us-east-1"))
        let (owner, _) = await snapshot(codeBuild, StatusQuery(target: .owner("acme")))
        guard case .configuration(let message) = owner.error else {
            Issue.record("expected a configuration error, got \(String(describing: owner.error))")
            return
        }
        #expect(message.contains("no owners"))
    }

    @Test("pages back through builds until they are older than a build can go on")
    func paging() async throws {
        var codeBuild = FakeCodeBuild()
        codeBuild.pageSize = 2
        // Builds go on for at most an hour here: 15 queued, 30 running, 15 to finish up.
        codeBuild.projects = [AWSFixtures.project("runner", timeout: 30, queuedTimeout: 15)]
        codeBuild.builds["runner"] = [
            AWSFixtures.build("runner", 5, phase: "BUILD", minutesAgo: 2),
            AWSFixtures.build("runner", 4, phase: "COMPLETED", status: "SUCCEEDED", minutesAgo: 10),
            AWSFixtures.build("runner", 3, phase: "BUILD", minutesAgo: 40),
            AWSFixtures.build("runner", 2, phase: "COMPLETED", status: "SUCCEEDED", minutesAgo: 70),
            // Past the cutoff, so never read, though it claims to be unfinished.
            AWSFixtures.build("runner", 1, phase: "BUILD", minutesAgo: 80),
        ]
        let (result, stub) = await snapshot(codeBuild)
        #expect(Set(try result.get().runs.map(\.run.number)) == [5, 3])
        let listings = stub.requests.filter {
            $0.headers["X-Amz-Target"] == "CodeBuild_20161006.ListBuildsForProject"
        }
        #expect(listings.count == 2)
    }

    @Test("reads a build again to learn how it ended")
    func latest() async throws {
        var codeBuild = codeBuild
        let service = makeService(codeBuild.transport())
        let snapshot = try await RunsMonitor(service: service, now: { Fixtures.now })
            .snapshot(StatusQuery())
            .get()
        let running = try #require(snapshot.runs.first { $0.run.number == 11 })
        codeBuild.builds["api-runner"] = [
            AWSFixtures.build("api-runner", 11, phase: "COMPLETED", status: "TIMED_OUT")
        ]
        let ended = try await makeService(codeBuild.transport())
            .latest(running, query: StatusQuery())
            .get()
        #expect(ended.run.status == .completed)
        #expect(ended.run.conclusion == .timedOut)
        #expect(ended.repository == running.repository)
        #expect(ended.jobs?.first?.conclusion == .timedOut)
    }

    @Test("signs every call for CodeBuild in the endpoint's region")
    func signed() async throws {
        let (result, stub) = await snapshot(codeBuild)
        _ = try result.get()
        #expect(!stub.requests.isEmpty)
        for request in stub.requests {
            #expect(request.method == "POST")
            #expect(request.headers["Content-Type"] == "application/x-amz-json-1.1")
            #expect(request.headers["X-Amz-Target"]?.hasPrefix("CodeBuild_20161006.") == true)
            #expect(
                request.headers["Authorization"]?.hasPrefix(
                    "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20270115/us-east-1/codebuild/aws4_request"
                ) == true
            )
        }
    }

    @Test("retries throttling, signing each attempt at the time it is sent")
    func throttled() async throws {
        let clock = Atomic(0)
        let codeBuild = codeBuild
        let stub = StubTransport { request, attempt in
            attempt == 0
                ? .raw(400, #"{"__type":"ThrottlingException","message":"Rate exceeded"}"#)
                : codeBuild.respond(request)
        }
        let service = makeService(stub, retryPolicy: .limitRetries(1)) {
            Fixtures.now.addingTimeInterval(Double(clock.add(1, ordering: .relaxed).newValue))
        }
        let run = ActiveRun(
            repository: Fixtures.repository("api-runner"),
            run: AWSFixtures.build("api-runner", 11).run(in: AWSFixtures.region)
        )
        let latest = try await service.latest(run, query: StatusQuery()).get()
        #expect(latest.run.number == 11)
        let dates = stub.requests.map { $0.headers["X-Amz-Date"] }
        #expect(dates.count == 2)
        #expect(dates[0] != dates[1])
    }

    @Test("shows each build with its repository, its compute, and its phase or what it waits for")
    func report() async throws {
        let (result, _) = await snapshot(codeBuild)
        let lines = TextReport(now: Fixtures.now).render(try result.get())
            .components(separatedBy: "\n")
        let header = "AWS CodeBuild · 2 active runs in 1 of 3 projects · "
        #expect(lines.first?.hasPrefix(header) == true)
        let console = "https://us-east-1.console.aws.amazon.com/codesuite/codebuild/123456789012"
        #expect(
            Array(lines.dropFirst(2).prefix(9)) == [
                "api-runner",
                "  ○ api-runner #12  octo/app",
                "    queued 1m 00s · main · webhook · 0/1 jobs done",
                "    \(console)/projects/api-runner/build/api-runner%3Auuid-12/?region=us-east-1",
                "    ○ BUILD_GENERAL1_SMALL queued 1m 00s LINUX_CONTAINER",
                "  ● api-runner #11  octo/app",
                "    running 3m 00s · main · webhook · 0/1 jobs done",
                "    \(console)/projects/api-runner/build/api-runner%3Auuid-11/?region=us-east-1",
                "    ● BUILD_GENERAL1_SMALL 3m 00s amazonlinux-x86_64-standard:5.0 → build",
            ]
        )
    }

    @Test("fails every call when the endpoint names no region")
    func noRegion() async {
        let service = AWSService(
            credentials: AWSFixtures.credentials,
            endpoint: Fixtures.url("http://localhost:4566"),
            transport: codeBuild.transport()
        )
        guard case .configuration(let message) = await service.scope(for: StatusQuery()).error
        else {
            Issue.record("expected a configuration error")
            return
        }
        #expect(message.contains("names no AWS region"))
    }
}

extension Result {
    var error: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
