import Foundation
import Testing

@testable import RunnersKit

@Suite("GitHub mapping")
struct GitHubMappingTests {
    @Test("reads a run, ignoring fields it does not model")
    func run() throws {
        let json = """
            {
              "id": 43728663493, "name": "Tests", "node_id": "WFR_x", "head_branch": "main",
              "head_sha": "0a1b2c", "path": ".github/workflows/tests.yml", "display_title": "Fix it",
              "run_number": 83, "event": "push", "status": "queued", "conclusion": null,
              "workflow_id": 1, "html_url": "https://github.com/octo/repo/actions/runs/43728663493",
              "created_at": "2026-11-15T15:13:09Z", "updated_at": "2026-11-15T15:13:20Z",
              "run_attempt": 2, "run_started_at": "2026-11-15T15:13:09Z",
              "actor": { "login": "octo", "id": 1, "type": "User", "site_admin": false },
              "pull_requests": [], "repository": { "id": 9, "full_name": "octo/repo" }
            }
            """
        let run = try JSONCoding.decode(GitHubWorkflowRun.self, from: Data(json.utf8)).get().run

        #expect(run.id == "43728663493")
        #expect(run.name == "Tests")
        #expect(run.title == "Fix it")
        #expect(run.number == 83)
        #expect(run.attempt == 2)
        #expect(run.trigger == "push")
        #expect(run.status == .queued)
        #expect(run.conclusion == nil)
        #expect(run.branch == "main")
        #expect(run.actor == "octo")
    }

    @Test("reads a job with its runner and the step in progress")
    func job() throws {
        let json = """
            {
              "id": 7, "run_id": 3, "name": "Test macOS", "status": "in_progress", "conclusion": null,
              "created_at": "2026-11-15T15:00:00Z", "started_at": "2026-11-15T15:01:00Z",
              "completed_at": null, "labels": ["macos-26"], "runner_id": 1000003184,
              "runner_name": "GitHub Actions 1000003184", "runner_group_name": "GitHub Actions",
              "html_url": "https://github.com/octo/repo/actions/runs/3/job/7",
              "steps": [
                { "name": "Set up job", "status": "completed", "conclusion": "success", "number": 1 },
                { "name": "Run tests", "status": "in_progress", "conclusion": null, "number": 2 }
              ]
            }
            """
        let job = try JSONCoding.decode(GitHubWorkflowJob.self, from: Data(json.utf8)).get().job

        #expect(job.status == .running)
        #expect(job.runner == "GitHub Actions 1000003184")
        #expect(job.labels == ["macos-26"])
        #expect(job.currentStep == "Run tests")
        #expect(job.stage == nil)
    }

    @Test(
        "maps GitHub statuses",
        arguments: [
            ("queued", RunStatus.queued), ("requested", .queued), ("pending", .pending),
            ("waiting", .waiting),
            ("in_progress", .running), ("completed", .completed), ("hibernating", .unknown),
        ]
    )
    func statuses(raw: String, status: RunStatus) {
        #expect(RunStatus(gitHub: raw) == status)
    }

    @Test(
        "maps GitHub conclusions",
        arguments: [
            ("success", Conclusion.success), ("failure", .failure), ("startup_failure", .failure),
            ("timed_out", .timedOut), ("cancelled", .cancelled), ("stale", .neutral),
            ("vaporized", .unknown),
        ]
    )
    func conclusions(raw: String, conclusion: Conclusion) {
        #expect(Conclusion(gitHub: raw) == conclusion)
    }

    @Test("asks for each unfinished status by its GitHub name")
    func queryValues() {
        #expect(
            RunStatus.active.flatMap(\.gitHubQueryValues) == [
                "in_progress", "queued", "waiting", "pending",
            ]
        )
        #expect(RunStatus.completed.gitHubQueryValues.isEmpty)
    }

    @Test("picks the listing that sees the most repositories")
    func listings() {
        let other = GitHubAccount(id: 3, login: "hubot", type: "User")
        let meShouting = GitHubAccount(id: 1, login: "OCTO", type: "User")

        #expect(
            GitHubListing.of(GitHubFixtures.org, viewer: GitHubFixtures.me) == .organization("acme")
        )
        #expect(GitHubListing.of(meShouting, viewer: GitHubFixtures.me) == .authenticatedUser)
        #expect(GitHubListing.of(other, viewer: GitHubFixtures.me) == .user("hubot"))
    }

    @Test("maps API URLs to gh hostnames")
    func hostnames() {
        #expect(GHCLI.hostname(forAPI: GitHubService.defaultBaseURL) == nil)
        #expect(
            GHCLI.hostname(forAPI: Fixtures.url("https://ghe.example.com/api/v3"))
                == "ghe.example.com"
        )
        #expect(GHCLI.hostname(forAPI: Fixtures.url("https://api.acme.ghe.com")) == "acme.ghe.com")
    }

    @Test("sends the token, API version and a user agent")
    func headers() {
        let headers = GitHubAPI.headers(token: "t0ken")
        #expect(headers["Authorization"] == "Bearer t0ken")
        #expect(headers["X-GitHub-Api-Version"] == GitHubAPI.version)
        #expect(headers["User-Agent"] != nil)
    }
}
