import FPRetry
import Foundation
import Testing

@testable import RunnersKit

@Suite("Runners")
struct RunnersListTests {
    static func githubRunner(
        _ id: Int,
        _ name: String,
        status: String = "online",
        busy: Bool = false,
        labels: [String] = ["self-hosted", "linux"]
    ) -> GitHubRunner {
        GitHubRunner(
            id: id,
            name: name,
            os: "Linux",
            status: status,
            busy: busy,
            ephemeral: false,
            labels: labels.map(GitHubRunner.Label.init(name:))
        )
    }

    static func gitlabRunner(
        _ id: Int,
        _ description: String,
        type: String = "group_type",
        status: String = "online",
        paused: Bool = false,
        execution: String? = "idle"
    ) -> GitLabRunner {
        GitLabRunner(
            id: id,
            description: description,
            name: nil,
            paused: paused,
            active: !paused,
            runnerType: type,
            online: status == "online",
            status: status,
            jobExecutionStatus: execution
        )
    }

    static let hosted = GitHubHostedRunner(
        id: 5,
        name: "ubuntu-large",
        platform: "linux-x64",
        status: "Ready",
        maximumRunners: 10,
        imageDetails: .init(displayName: "Ubuntu 24.04"),
        machineSizeDetails: .init(id: "4-core")
    )

    static let missingScope: [String: String] = [
        "X-Accepted-OAuth-Scopes": "admin:org",
        "X-OAuth-Scopes": "gist, read:org, repo",
    ]

    static let orgOnly = #"{"message":"You must be an org admin."}"#

    func github(
        _ query: StatusQuery,
        _ respond: @escaping @Sendable (String) -> HTTPResponse?
    ) async -> (Result<RunnersSnapshot, RunnersError>, StubTransport) {
        let stub = StubTransport { request, _ in
            let path = request.url.path()
            switch path {
                case "/user": return .json(GitHubFixtures.me)
                case "/users/acme": return .json(GitHubFixtures.org)
                case "/rate_limit": return .notFound
                default: return respond(path) ?? .notFound
            }
        }
        let service = GitHubService(token: "t", transport: stub, retryPolicy: .limitRetries(0))
        let monitor = RunsMonitor(service: service, now: { Fixtures.now })
        return (await monitor.runners(query), stub)
    }

    func gitlab(
        _ query: StatusQuery,
        _ respond: @escaping @Sendable (String) -> HTTPResponse?
    ) async -> (Result<RunnersSnapshot, RunnersError>, StubTransport) {
        let stub = StubTransport { request, _ in
            let path = String(request.url.path().dropFirst("/api/v4".count))
            switch path {
                case "/user": return .json(GitLabFixtures.me)
                case "/groups/acme": return .json(GitLabFixtures.group)
                default: return respond(path) ?? .notFound
            }
        }
        let service = GitLabService(token: "t", transport: stub, retryPolicy: .limitRetries(0))
        let monitor = RunsMonitor(service: service, now: { Fixtures.now })
        return (await monitor.runners(query), stub)
    }

    @Test("maps GitHub's runners, telling busy, idle and offline apart")
    func githubMapping() {
        let busy = Self.githubRunner(1, "mac-1", busy: true, labels: ["depot-ubuntu-24.04"])
            .runner
        #expect(busy.state == .busy)
        #expect(busy.kind == .selfHosted)
        #expect(busy.host == .depot)
        #expect(busy.labels == ["depot-ubuntu-24.04"])
        #expect(Self.githubRunner(2, "idle").runner.state == .idle)
        #expect(
            Self.githubRunner(3, "gone", status: "offline", busy: true).runner.state == .offline
        )

        let pool = Self.hosted.runner
        #expect(pool.kind == .githubHosted)
        #expect(pool.state == .idle)
        #expect(pool.busy == nil)
        #expect(pool.details == "linux-x64, 4-core, Ubuntu 24.04, up to 10")
    }

    @Test("lists an organization's runners and its larger runners")
    func organization() async throws {
        let (result, _) = await github(StatusQuery(target: .owner("acme"))) { path in
            switch path {
                case "/orgs/acme/actions/runners":
                    .json(
                        GitHubRunnersPage(
                            totalCount: 2,
                            runners: [
                                Self.githubRunner(1, "linux-2"), Self.githubRunner(2, "linux-1"),
                            ]
                        )
                    )
                case "/orgs/acme/actions/hosted-runners":
                    .json(GitHubHostedRunnersPage(totalCount: 1, runners: [Self.hosted]))
                default: nil
            }
        }
        let snapshot = try result.get()
        #expect(snapshot.owner == GitHubFixtures.org.owner)
        #expect(snapshot.runners.map(\.name) == ["linux-1", "linux-2", "ubuntu-large"])
        #expect(snapshot.notes.isEmpty)
    }

    @Test("leaves out larger runners the token may not list, and says why")
    func hostedDenied() async throws {
        let (result, _) = await github(StatusQuery(target: .owner("acme"))) { path in
            switch path {
                case "/orgs/acme/actions/runners":
                    .json(GitHubRunnersPage(totalCount: 1, runners: [Self.githubRunner(1, "a")]))
                case "/orgs/acme/actions/hosted-runners":
                    .raw(
                        403,
                        Self.orgOnly,
                        headers: [
                            "X-Accepted-OAuth-Scopes": "manage_runners:org",
                            "X-OAuth-Scopes": "repo",
                        ]
                    )
                default: nil
            }
        }
        let snapshot = try result.get()
        #expect(snapshot.runners.map(\.name) == ["a"])
        #expect(
            snapshot.notes == [
                "Larger GitHub-hosted runners left out: Access denied: You must be an org admin. "
                    + "The token needs the manage_runners:org scope and has repo; "
                    + "for gh's token, gh auth refresh -s manage_runners:org adds it."
            ]
        )
    }

    @Test("says which scope the token is missing when the organization's runners are denied")
    func organizationDenied() async {
        let (result, _) = await github(StatusQuery(target: .owner("acme"))) { path in
            path.hasPrefix("/orgs/acme/actions/")
                ? .raw(403, Self.orgOnly, headers: Self.missingScope) : nil
        }
        #expect(
            result.failure?.localizedDescription
                == "Access denied: You must be an org admin. The token needs the admin:org scope "
                + "and has gist, read:org, repo; for gh's token, gh auth refresh -s admin:org adds it."
        )
    }

    @Test("adds no scope hint when the token has an accepted scope, or has no scopes to compare")
    func scopeHint() {
        let has = HTTPResponse.raw(
            403,
            headers: ["X-Accepted-OAuth-Scopes": "repo", "X-OAuth-Scopes": "repo, gist"]
        )
        #expect(GitHubAPI.missingScope(has) == nil)
        let fineGrained = HTTPResponse.raw(403, headers: ["X-Accepted-OAuth-Scopes": "repo"])
        #expect(GitHubAPI.missingScope(fineGrained) == nil)
        let several = HTTPResponse.raw(
            403,
            headers: ["X-Accepted-OAuth-Scopes": "repo, public_repo", "X-OAuth-Scopes": ""]
        )
        #expect(
            GitHubAPI.missingScope(several)
                == "The token needs one of the scopes repo, public_repo and has none; "
                + "for gh's token, gh auth refresh -s repo adds it."
        )
    }

    @Test("lists each repository's runners for a user, counting those it may not list")
    func userRepositories() async throws {
        let repositories = [GitHubFixtures.repository("app"), GitHubFixtures.repository("web")]
        let (result, stub) = await github(StatusQuery()) { path in
            switch path {
                case "/user/repos": .json(repositories)
                case "/repos/octo/app/actions/runners":
                    .json(GitHubRunnersPage(totalCount: 1, runners: [Self.githubRunner(1, "box")]))
                case "/repos/octo/web/actions/runners": .raw(403, Self.orgOnly)
                default: nil
            }
        }
        let snapshot = try result.get()
        #expect(snapshot.owner == GitHubFixtures.me.owner)
        #expect(snapshot.runners.map(\.name) == ["box"])
        #expect(
            snapshot.notes == [
                "Runners of 1 of 2 repositories left out: "
                    + "listing them takes admin access to the repository."
            ]
        )
        #expect(!stub.paths.contains { $0.hasPrefix("/orgs/") })
    }

    @Test("maps GitLab's runners: kind, reachability, paused and busy")
    func gitlabMapping() {
        let busy = Self.gitlabRunner(1, "builder", type: "project_type", execution: "active")
        #expect(busy.runner().state == .busy)
        #expect(busy.runner().kind == .project)
        #expect(Self.gitlabRunner(2, "old", status: "stale").runner().state == .offline)
        #expect(
            Self.gitlabRunner(3, "new", status: "never_contacted").runner().status
                == .neverContacted
        )
        #expect(Self.gitlabRunner(4, "held", paused: true).runner().state == .paused)
        #expect(Self.gitlabRunner(5, "older", execution: nil).runner().busy == nil)
        #expect(Self.gitlabRunner(6, "", type: "instance_type").runner().name == "runner 6")
        #expect(Self.gitlabRunner(6, "", type: "instance_type").runner().kind == .instance)
    }

    @Test("lists a group's runners, with the jobs of busy ones, without the instance's")
    func group() async throws {
        let runners = [
            Self.gitlabRunner(1, "busy-1", execution: "active"),
            Self.gitlabRunner(2, "idle-1"),
            Self.gitlabRunner(3, "shared", type: "instance_type", execution: "active"),
        ]
        let job = GitLabRunnerJob(
            id: 77,
            name: "build",
            webURL: Fixtures.url("https://gitlab.com/acme/app/-/jobs/77"),
            project: .init(pathWithNamespace: "acme/app")
        )
        let (result, stub) = await gitlab(StatusQuery(target: .owner("acme"))) { path in
            switch path {
                case "/groups/50/runners": .json(runners)
                case "/runners/1/jobs": .json([job])
                default: nil
            }
        }
        let snapshot = try result.get()
        #expect(snapshot.runners.map(\.name) == ["busy-1", "idle-1"])
        #expect(snapshot.runners.first?.jobs.map(\.name) == ["build"])
        #expect(snapshot.runners.first?.jobs.first?.repository == "acme/app")
        #expect(
            snapshot.notes == [
                "1 instance runner left out: they belong to the instance, not to acme."
            ]
        )
        #expect(stub.paths.filter { $0.hasSuffix("/jobs") } == ["/api/v4/runners/1/jobs"])
        let jobsRequest = stub.requests.first { $0.url.path().hasSuffix("/jobs") }
        #expect(jobsRequest?.query("status") == "running")
    }

    @Test("says which role a group's runners take when they are denied")
    func groupDenied() async {
        let (result, _) = await gitlab(StatusQuery(target: .owner("acme"))) { path in
            path == "/groups/50/runners" ? .raw(403, #"{"message":"403 Forbidden"}"#) : nil
        }
        #expect(
            result.failure?.localizedDescription
                == "Access denied: 403 Forbidden; listing a group's runners takes the Owner role "
                + "in the group and a token with the manage_runner scope."
        )
    }

    @Test("lists the runners the token's user can manage on GitLab")
    func gitlabUser() async throws {
        let (result, _) = await gitlab(StatusQuery()) { path in
            path == "/runners" ? .json([Self.gitlabRunner(1, "mine", type: "project_type")]) : nil
        }
        let snapshot = try result.get()
        #expect(snapshot.owner == GitLabFixtures.me.owner)
        #expect(snapshot.runners.map(\.name) == ["mine"])
        #expect(snapshot.notes.isEmpty)
    }

    @Test("lists each project's runners once, counting projects it may not list")
    func gitlabProjects() async throws {
        let app = GitLabFixtures.project("acme/app", id: 11)
        let web = GitLabFixtures.project("acme/web", id: 12)
        let shared = Self.gitlabRunner(1, "group-box")
        let query = StatusQuery(target: .repositories(["acme/app", "acme/web", "acme/api"]))
        let api = GitLabFixtures.project("acme/api", id: 13)
        let (result, _) = await gitlab(query) { path in
            switch path {
                case "/projects/acme%2Fapp": .json(app)
                case "/projects/acme%2Fweb": .json(web)
                case "/projects/acme%2Fapi": .json(api)
                case "/projects/11/runners": .json([shared, Self.gitlabRunner(2, "app-box")])
                case "/projects/12/runners": .json([shared])
                case "/projects/13/runners": .raw(403, #"{"message":"403 Forbidden"}"#)
                default: nil
            }
        }
        let snapshot = try result.get()
        #expect(snapshot.owner == nil)
        #expect(snapshot.runners.map(\.name) == ["app-box", "group-box"])
        #expect(
            snapshot.notes == [
                "Runners of 1 of 3 projects left out: listing them takes the Maintainer role."
            ]
        )
    }

    @Test("fails for a service without runners of its own")
    func unsupported() async {
        let service = AWSService(
            credentials: AWSCredentials(accessKeyID: "AKID", secretAccessKey: "s"),
            endpoint: Fixtures.url("https://codebuild.us-east-1.amazonaws.com"),
            transport: StubTransport { _, _ in .notFound }
        )
        let result = await service.runners(for: StatusQuery())
        #expect(
            result.failure?.localizedDescription
                == "Configuration: AWS CodeBuild has no runners to list; "
                + "--runners works with GitHub and GitLab."
        )
    }

    var snapshot: RunnersSnapshot {
        RunnersSnapshot(
            provider: GitHubProvider(),
            listing: RunnerListing(
                owner: GitHubFixtures.org.owner,
                runners: [
                    Self.githubRunner(3, "old-box", status: "offline").runner,
                    Self.githubRunner(1, "linux-1").runner,
                    Runner(
                        id: "7",
                        name: "builder",
                        kind: .group,
                        status: .online,
                        busy: true,
                        jobs: [
                            RunnerJob(id: "1", name: "build", repository: "acme/app", webURL: nil),
                            RunnerJob(id: "2", name: "test", repository: "acme/app", webURL: nil),
                        ]
                    ),
                    Self.githubRunner(2, "depot-1", busy: true, labels: ["depot-ubuntu-24.04"])
                        .runner,
                    Self.hosted.runner,
                ],
                notes: ["Larger GitHub-hosted runners left out: denied."]
            ),
            rateLimit: nil,
            fetchedAt: Fixtures.now
        )
    }

    @Test("reports runners grouped by state, busy first, then what was left out")
    func report() {
        let time = Fixtures.now.formatted(date: .omitted, time: .standard)
        #expect(
            TextReport(now: Fixtures.now).render(snapshot).components(separatedBy: "\n") == [
                "acme on GitHub · 5 runners, 2 busy · \(time)",
                "",
                "Busy",
                "  ● builder      group runner → build (acme/app) +1 more",
                "  ● depot-1      Depot · Linux · depot-ubuntu-24.04",
                "",
                "Idle",
                "  ○ linux-1      Linux · self-hosted, linux",
                "  ○ ubuntu-large GitHub-hosted · linux-x64, 4-core, Ubuntu 24.04, up to 10",
                "",
                "Offline",
                "  ✗ old-box      offline · Linux · self-hosted, linux",
                "",
                "Larger GitHub-hosted runners left out: denied.",
            ]
        )
    }

    @Test("carries each runner's state, vendor and jobs in the JSON")
    func json() throws {
        let json = try snapshot.json().get()
        #expect(json.contains(#""state" : "busy""#))
        #expect(json.contains(#""host" : "depot""#))
        #expect(json.contains(#""kind" : "github_hosted""#))
        #expect(json.contains(#""notes" : ["#))
        let runner = snapshot.runners[0]
        let data = try JSONEncoder().encode(runner)
        #expect(try JSONDecoder().decode(Runner.self, from: data) == runner)
    }
}

extension Result {
    var failure: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
