import FPRetry
import Foundation
import Testing

@testable import RunnersKit

@Suite("GitHub service")
struct GitHubServiceTests {
    let active = GitHubFixtures.repository("active")
    let quiet = GitHubFixtures.repository("quiet")
    let archived = GitHubFixtures.repository("archived", isArchived: true)
    let disabled = GitHubFixtures.repository("disabled", isDisabled: true)
    let fork = GitHubFixtures.repository("fork", isFork: true)

    var github: FakeGitHub {
        var github = FakeGitHub()
        github.listings["/user/repos"] = [active, quiet, archived, disabled, fork]
        github.workflowCounts = [
            "octo/active": 2, "octo/archived": 1, "octo/disabled": 1, "octo/fork": 1,
        ]
        github.runs["octo/active"] = [
            "in_progress": [GitHubFixtures.run(1, "in_progress", minutesAgo: 5)],
            "queued": [GitHubFixtures.run(2, "queued", minutesAgo: 2)],
        ]
        github.runs["octo/fork"] = ["in_progress": [GitHubFixtures.run(3, "in_progress")]]
        github.jobs[1] = [GitHubFixtures.job(10, "test", "in_progress", runner: "runner-1")]
        github.jobs[2] = [GitHubFixtures.job(20, "build", "queued")]
        return github
    }

    func snapshot(
        _ github: FakeGitHub,
        _ query: StatusQuery = StatusQuery()
    ) async -> (Result<StatusSnapshot, RunnersError>, StubTransport) {
        let stub = github.transport()
        let service = GitHubService(token: "t", transport: stub, retryPolicy: .limitRetries(0))
        let monitor = RunsMonitor(service: service, now: { Fixtures.now })
        return (await monitor.snapshot(query), stub)
    }

    @Test("finds the unfinished runs of the user's repositories, newest first, with jobs")
    func authenticatedUser() async throws {
        let (result, stub) = await snapshot(github)
        let snapshot = try result.get()

        #expect(snapshot.provider.id == "github")
        #expect(snapshot.owner == Owner(id: "1", login: "octo", kind: .user))
        #expect(snapshot.repositoryCount == 2)
        #expect(snapshot.runs.map(\.run.id) == ["2", "1"])
        #expect(snapshot.runs.map { $0.jobs?.map(\.name) } == [["build"], ["test"]])
        #expect(snapshot.runs.first?.jobs?.first?.status == .queued)
        #expect(snapshot.rateLimit == GitHubFixtures.rateLimit.rateLimit)
        #expect(snapshot.fetchedAt == Fixtures.now)
        #expect(
            stub.requests.first { $0.url.path() == "/user/repos" }?.query("affiliation") == "owner"
        )
    }

    @Test("asks only repositories with workflows that can run them, once per status")
    func requests() async {
        let (_, stub) = await snapshot(github)
        let runRequests = stub.requests.filter { $0.url.path().hasSuffix("/actions/runs") }

        #expect(
            !stub.paths.contains {
                $0.contains("archived") || $0.contains("disabled") || $0.contains("fork")
            }
        )
        #expect(!stub.paths.contains("/repos/octo/quiet/actions/runs"))
        #expect(
            Set(runRequests.compactMap { $0.query("status") }) == [
                "in_progress", "queued", "waiting", "pending",
            ]
        )
        #expect(runRequests.allSatisfy { $0.url.path() == "/repos/octo/active/actions/runs" })
    }

    @Test("asks only for the statuses wanted")
    func someStatuses() async throws {
        let (result, stub) = await snapshot(github, StatusQuery(statuses: [.running]))

        #expect(try result.get().runs.map(\.run.id) == ["1"])
        #expect(stub.requests.compactMap { $0.query("status") } == ["in_progress"])
    }

    @Test("includes forks when asked")
    func forks() async throws {
        let snapshot = try await snapshot(github, StatusQuery(includeForks: true)).0.get()

        #expect(snapshot.repositoryCount == 3)
        #expect(Set(snapshot.runs.map(\.repository.name)) == ["active", "fork"])
    }

    @Test("lists an organization's repositories")
    func organization() async throws {
        let repo = GitHubFixtures.repository("api", owner: GitHubFixtures.org)
        var github = FakeGitHub()
        github.accounts["acme"] = GitHubFixtures.org
        github.listings["/orgs/acme/repos"] = [repo]
        github.workflowCounts["acme/api"] = 1
        github.runs["acme/api"] = ["waiting": [GitHubFixtures.run(5, "waiting")]]

        let (result, stub) = await snapshot(github, StatusQuery(target: .owner("acme")))
        let snapshot = try result.get()

        #expect(snapshot.owner?.kind == .organization)
        #expect(snapshot.runs.map(\.run.status) == [.waiting])
        #expect(stub.requests.first { $0.url.path() == "/orgs/acme/repos" }?.query("type") == "all")
    }

    @Test("checks named repositories without listing an owner")
    func namedRepositories() async throws {
        let (result, stub) = await snapshot(
            github,
            StatusQuery(target: .repositories(["octo/active"]))
        )
        let snapshot = try result.get()

        #expect(snapshot.owner == nil)
        #expect(snapshot.repositoryCount == 1)
        #expect(snapshot.runs.count == 2)
        #expect(!stub.paths.contains("/user/repos"))
    }

    @Test("lists a run once when it changes status between two requests")
    func duplicates() async throws {
        var github = github
        github.runs["octo/active"]?["queued"]?.append(
            GitHubFixtures.run(1, "in_progress", minutesAgo: 5)
        )

        #expect(try await snapshot(github).0.get().runs.map(\.run.id) == ["2", "1"])
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

        #expect(
            await snapshot(github).0.map(\.runs.count) == .failure(.unauthorized("Bad credentials"))
        )
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

@Suite("GitHub latest run")
struct GitHubLatestTests {
    @Test("reads a run that dropped out, with when it finished and its jobs")
    func latest() async throws {
        var github = FakeGitHub()
        github.runsByID[1] = GitHubFixtures.run(
            1,
            "completed",
            conclusion: "failure",
            updatedMinutesAgo: 1
        )
        github.jobs[1] = [GitHubFixtures.job(10, "test", "completed")]
        let service = GitHubService(
            token: "t",
            transport: github.transport(),
            retryPolicy: .limitRetries(0)
        )
        let repository = Fixtures.repository("octo/repo")
        let before = ActiveRun(
            repository: repository,
            run: GitHubFixtures.run(1, "in_progress").run
        )
        let after = try await service.latest(before, query: StatusQuery()).get()
        #expect(after.run.status == .completed)
        #expect(after.run.conclusion == .failure)
        #expect(after.run.completedAt == Fixtures.minutesAgo(1))
        #expect(after.jobs?.map(\.name) == ["test"])
    }
}
