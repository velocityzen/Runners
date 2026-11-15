import FPRetry
import Foundation
import Testing

@testable import RunnersKit

@Suite("Actions monitor")
struct ActionsMonitorTests {
    let active = Fixtures.repository("active")
    let quiet = Fixtures.repository("quiet")
    let archived = Fixtures.repository("archived", isArchived: true)
    let fork = Fixtures.repository("fork", isFork: true)
    let running = Fixtures.run(1, .inProgress, minutesAgo: 5)
    let queued = Fixtures.run(2, .queued, minutesAgo: 2)

    var github: FakeGitHub {
        var github = FakeGitHub()
        github.listings["/user/repos"] = [active, quiet, archived, fork]
        github.workflowCounts = ["octo/active": 2, "octo/archived": 1, "octo/fork": 1]
        github.runs["octo/active"] = [.inProgress: [running], .queued: [queued]]
        github.runs["octo/fork"] = [.inProgress: [Fixtures.run(3, .inProgress)]]
        github.jobs[1] = [Fixtures.job(10, "test", .inProgress, runner: "runner-1")]
        github.jobs[2] = [Fixtures.job(20, "build", .queued)]
        return github
    }

    func snapshot(
        _ github: FakeGitHub,
        _ query: StatusQuery = StatusQuery()
    ) async -> (Result<StatusSnapshot, GitHubError>, StubTransport) {
        let stub = github.transport()
        let client = GitHubClient(token: "t", transport: stub, retryPolicy: .limitRetries(0))
        let monitor = ActionsMonitor(client: client, now: { Fixtures.now })
        return (await monitor.snapshot(query), stub)
    }

    @Test("finds the unfinished runs of the user's repositories, newest first, with jobs")
    func authenticatedUser() async throws {
        let (result, stub) = await snapshot(github)
        let snapshot = try result.get()

        #expect(snapshot.owner == Fixtures.me)
        #expect(snapshot.repositoryCount == 2)
        #expect(snapshot.runs.map(\.id) == [2, 1])
        #expect(snapshot.runs.map { $0.jobs?.map(\.id) } == [[20], [10]])
        #expect(snapshot.rateLimit == Fixtures.rateLimit)
        #expect(snapshot.fetchedAt == Fixtures.now)
        #expect(stub.requests.first { $0.url.path() == "/user/repos" }?.query("affiliation") == "owner")
    }

    @Test("asks only repositories that can run workflows, once per status")
    func requests() async {
        let (_, stub) = await snapshot(github)
        let runRequests = stub.requests.filter { $0.url.path().hasSuffix("/actions/runs") }

        #expect(!stub.paths.contains { $0.contains("archived") || $0.contains("fork") })
        #expect(!stub.paths.contains("/repos/octo/quiet/actions/runs"))
        #expect(Set(runRequests.compactMap { $0.query("status") }) == Set(ActionStatus.active.map(\.rawValue)))
        #expect(runRequests.allSatisfy { $0.url.path() == "/repos/octo/active/actions/runs" })
    }

    @Test("includes forks when asked")
    func forks() async throws {
        let snapshot = try await snapshot(github, StatusQuery(includeForks: true)).0.get()

        #expect(snapshot.repositoryCount == 3)
        #expect(Set(snapshot.runs.map(\.repository.name)) == ["active", "fork"])
    }

    @Test("lists an organization's repositories")
    func organization() async throws {
        let repo = Fixtures.repository("api", owner: Fixtures.org)
        var github = FakeGitHub()
        github.accounts["acme"] = Fixtures.org
        github.listings["/orgs/acme/repos"] = [repo]
        github.workflowCounts["acme/api"] = 1
        github.runs["acme/api"] = [.waiting: [Fixtures.run(5, .waiting)]]

        let (result, stub) = await snapshot(github, StatusQuery(target: .owner("acme")))
        let snapshot = try result.get()

        #expect(snapshot.owner == Fixtures.org)
        #expect(snapshot.runs.map(\.run.status) == [.waiting])
        #expect(stub.requests.first { $0.url.path() == "/orgs/acme/repos" }?.query("type") == "all")
    }

    @Test("lists another user's public repositories")
    func otherUser() async throws {
        let hubot = Account(id: 9, login: "hubot", kind: .user)
        var github = FakeGitHub()
        github.accounts["hubot"] = hubot
        github.listings["/users/hubot/repos"] = [Fixtures.repository("bot", owner: hubot)]

        let (result, stub) = await snapshot(github, StatusQuery(target: .owner("hubot")))

        #expect(try result.get().owner == hubot)
        #expect(stub.paths.contains("/users/hubot/repos"))
    }

    @Test("checks named repositories without listing an owner")
    func namedRepositories() async throws {
        let (result, stub) = await snapshot(github, StatusQuery(target: .repositories(["octo/active"])))
        let snapshot = try result.get()

        #expect(snapshot.owner == nil)
        #expect(snapshot.repositoryCount == 1)
        #expect(snapshot.runs.count == 2)
        #expect(!stub.paths.contains("/user/repos"))
    }

    @Test("lists a run once when it changes status between two requests")
    func duplicates() async throws {
        var github = github
        github.runs["octo/active"] = [.inProgress: [running], .queued: [running, queued]]

        let snapshot = try await snapshot(github).0.get()

        #expect(snapshot.runs.map(\.id) == [2, 1])
    }

    @Test("skips the jobs when not asked for them")
    func withoutJobs() async throws {
        let (result, stub) = await snapshot(github, StatusQuery(includeJobs: false))

        #expect(try result.get().runs.allSatisfy { $0.jobs == nil })
        #expect(!stub.paths.contains { $0.hasSuffix("/jobs") })
    }

    @Test("fails as a whole when a request fails")
    func failure() async {
        var github = github
        github.runsFailure = .raw(401, #"{"message":"Bad credentials"}"#)

        let (result, _) = await snapshot(github)

        #expect(result.map(\.runs.count) == .failure(.unauthorized("Bad credentials")))
    }

    @Test("reports an unknown owner")
    func unknownOwner() async {
        let (result, _) = await snapshot(github, StatusQuery(target: .owner("nobody")))

        #expect(result.map(\.runs.count) == .failure(.notFound("/users/nobody")))
    }

    @Test("does without a rate limit when the server has none")
    func noRateLimit() async throws {
        var github = github
        github.rateLimit = nil

        #expect(try await snapshot(github).0.get().rateLimit == nil)
    }
}
