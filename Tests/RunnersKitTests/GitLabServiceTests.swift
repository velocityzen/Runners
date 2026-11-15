import FPRetry
import Foundation
import Testing

@testable import RunnersKit

@Suite("GitLab service")
struct GitLabServiceTests {
    let api = GitLabFixtures.project("acme/api", id: 1)
    let web = GitLabFixtures.project("acme/frontend/web", id: 2)
    let quiet = GitLabFixtures.project("acme/quiet", id: 3)
    let off = GitLabFixtures.project("acme/off", id: 4, builds: "disabled")
    let fork = GitLabFixtures.project("acme/fork", id: 5, isFork: true)

    var gitlab: FakeGitLab {
        var gitlab = FakeGitLab()
        gitlab.groups["acme"] = GitLabFixtures.group
        gitlab.listings["/groups/50/projects"] = [api, web, quiet, off, fork]
        gitlab.projectJobs[1] = [
            GitLabFixtures.job(100, "rspec", "running", pipeline: 10, runner: "shared-1"),
            GitLabFixtures.job(101, "deploy", "created", pipeline: 10, stage: "deploy"),
            GitLabFixtures.job(102, "approve", "manual", pipeline: 9, pipelineStatus: "success"),
        ]
        gitlab.projectJobs[2] = [
            GitLabFixtures.job(200, "build", "pending", pipeline: 20, pipelineStatus: "pending")
        ]
        gitlab.projectJobs[5] = [GitLabFixtures.job(500, "build", "running", pipeline: 50)]
        gitlab.pipelines[10] = GitLabFixtures.pipeline(10, "running", minutesAgo: 8)
        gitlab.pipelines[20] = GitLabFixtures.pipeline(20, "pending", minutesAgo: 1)
        gitlab.pipelines[50] = GitLabFixtures.pipeline(50, "running")
        gitlab.pipelineJobs[10] =
            [
                GitLabFixtures.job(99, "lint", "success", pipeline: 10, stage: "build")
            ] + (gitlab.projectJobs[1] ?? []).prefix(2)
        gitlab.pipelineJobs[20] = gitlab.projectJobs[2] ?? []
        return gitlab
    }

    func snapshot(
        _ gitlab: FakeGitLab,
        _ query: StatusQuery = StatusQuery(target: .owner("acme"))
    ) async -> (Result<StatusSnapshot, RunnersError>, StubTransport) {
        let stub = gitlab.transport()
        let service = GitLabService(token: "t", transport: stub, retryPolicy: .limitRetries(0))
        let monitor = RunsMonitor(service: service, now: { Fixtures.now })
        return (await monitor.snapshot(query), stub)
    }

    @Test("finds a group's unfinished pipelines, subgroups included, with jobs")
    func group() async throws {
        let (result, stub) = await snapshot(gitlab)
        let snapshot = try result.get()

        #expect(snapshot.provider.id == "gitlab")
        #expect(snapshot.owner == Owner(id: "50", login: "acme", kind: .organization))
        #expect(snapshot.repositoryCount == 3)
        #expect(snapshot.runs.map(\.repository.fullName) == ["acme/api", "acme/frontend/web"])
        #expect(snapshot.runs.map(\.run.id) == ["10", "20"])
        #expect(snapshot.runs.first?.run.title == "Commit for 10")
        #expect(snapshot.runs.first?.jobs?.map(\.name) == ["lint", "rspec", "deploy"])
        #expect(snapshot.runs.first?.jobs?.map(\.stage) == ["build", "test", "deploy"])
        #expect(snapshot.rateLimit == nil)
        #expect(
            stub.requests.first { $0.url.path() == "/api/v4/groups/50/projects" }?.query(
                "include_subgroups"
            ) == "true"
        )
    }

    @Test("asks each project once for its unfinished jobs, leaving out manual ones")
    func requests() async {
        let (_, stub) = await snapshot(gitlab)
        let jobRequests = stub.requests.filter {
            $0.url.path().hasSuffix("/jobs") && !$0.url.path().contains("pipelines")
        }

        #expect(
            Set(jobRequests.map { $0.url.path() }) == [
                "/api/v4/projects/1/jobs", "/api/v4/projects/2/jobs", "/api/v4/projects/3/jobs",
            ]
        )
        #expect(jobRequests.count == 3)
        #expect(jobRequests.allSatisfy { !$0.queryValues("scope[]").contains("manual") })
        #expect(jobRequests.first?.queryValues("scope[]").contains("running") == true)
        #expect(!stub.paths.contains("/api/v4/projects/1/pipelines/9"))
    }

    @Test("shows only the statuses wanted")
    func someStatuses() async throws {
        let (result, stub) = await snapshot(
            gitlab,
            StatusQuery(target: .owner("acme"), statuses: [.queued])
        )

        #expect(try result.get().runs.map(\.run.id) == ["20"])
        #expect(!stub.paths.contains("/api/v4/projects/1/pipelines/10"))
    }

    @Test("falls back to a user when no group has the name")
    func user() async throws {
        var gitlab = FakeGitLab()
        gitlab.users["hubot"] = GitLabUser(id: 9, username: "hubot")
        gitlab.listings["/users/9/projects"] = [quiet]

        let (result, stub) = await snapshot(gitlab, StatusQuery(target: .owner("hubot")))

        #expect(try result.get().owner == Owner(id: "9", login: "hubot", kind: .user))
        #expect(stub.paths.contains("/api/v4/users/9/projects"))
    }

    @Test("reports a name that is neither group nor user")
    func unknownNamespace() async {
        let (result, _) = await snapshot(FakeGitLab(), StatusQuery(target: .owner("nobody")))

        #expect(
            result.map(\.runs.count) == .failure(.notFound("no GitLab group or user named nobody"))
        )
    }

    @Test("lists the projects the token's user owns")
    func authenticatedUser() async throws {
        var gitlab = gitlab
        gitlab.listings["/projects"] = [api]

        let (result, stub) = await snapshot(gitlab, StatusQuery())

        #expect(try result.get().owner == Owner(id: "1", login: "octo", kind: .user))
        #expect(
            stub.requests.first { $0.url.path() == "/api/v4/projects" }?.query("owned") == "true"
        )
    }

    @Test("looks up named projects by escaped path")
    func namedProjects() async throws {
        let (result, stub) = await snapshot(
            gitlab,
            StatusQuery(target: .repositories(["acme/frontend/web"]))
        )

        #expect(try result.get().runs.map(\.run.id) == ["20"])
        #expect(stub.encodedPaths.contains("/api/v4/projects/acme%2Ffrontend%2Fweb"))
    }

    @Test("includes forks when asked")
    func forks() async throws {
        let snapshot = try await snapshot(
            gitlab,
            StatusQuery(target: .owner("acme"), includeForks: true)
        ).0.get()

        #expect(snapshot.runs.map(\.repository.name).contains("fork"))
    }

    @Test("skips the jobs when not asked for them")
    func withoutJobs() async throws {
        let (result, stub) = await snapshot(
            gitlab,
            StatusQuery(target: .owner("acme"), includeJobs: false)
        )

        #expect(try result.get().runs.allSatisfy { $0.jobs == nil })
        #expect(!stub.paths.contains { $0.contains("/pipelines/") && $0.hasSuffix("/jobs") })
    }
}

@Suite("GitLab latest run")
struct GitLabLatestTests {
    @Test("reads a pipeline that dropped out, keeping its title")
    func latest() async throws {
        var gitlab = FakeGitLab()
        gitlab.pipelines[42] = GitLabFixtures.pipeline(42, "success", finishedMinutesAgo: 1)
        let service = GitLabService(
            token: "t",
            transport: gitlab.transport(),
            retryPolicy: .limitRetries(0)
        )
        let repository = Fixtures.repository("acme/api", id: "5")
        let before = ActiveRun(
            repository: repository,
            run: GitLabFixtures.pipeline(42, "running").run(title: "Fix it", actor: "octo")
        )
        let after = try await service.latest(before, query: StatusQuery(includeJobs: false)).get()
        #expect(after.run.status == .completed)
        #expect(after.run.conclusion == .success)
        #expect(after.run.title == "Fix it")
        #expect(after.run.completedAt == Fixtures.minutesAgo(1))
        #expect(after.jobs == nil)
    }
}
