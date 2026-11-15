import Foundation
import Testing

@testable import RunnersKit

@Suite("Decoding GitHub JSON")
struct DecodingTests {
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
        let run = try GitHubJSON.decode(WorkflowRun.self, from: Data(json.utf8)).get()
        #expect(run.id == 43_728_663_493)
        #expect(run.status == .queued)
        #expect(run.conclusion == nil)
        #expect(run.runAttempt == 2)
        #expect(run.displayTitle == "Fix it")
        #expect(run.actor?.kind == .user)
        #expect(run.createdAt == ISO8601DateFormatter().date(from: "2026-11-15T15:13:09Z"))
    }

    @Test("reads a job with its runner and steps")
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
        let job = try GitHubJSON.decode(WorkflowJob.self, from: Data(json.utf8)).get()
        #expect(job.runnerName == "GitHub Actions 1000003184")
        #expect(job.labels == ["macos-26"])
        #expect(job.currentStep?.name == "Run tests")
        #expect(job.completedAt == nil)
    }

    @Test("keeps going when GitHub adds a status, conclusion or account type")
    func unknownValues() throws {
        let job = """
            { "id": 1, "run_id": 1, "name": "x", "status": "hibernating", "conclusion": "vaporized", "labels": [] }
            """
        let decoded = try GitHubJSON.decode(WorkflowJob.self, from: Data(job.utf8)).get()
        #expect(decoded.status == .unknown)
        #expect(decoded.conclusion == .unknown)

        let account = #"{ "id": 1, "login": "ghost", "type": "Mannequin" }"#
        #expect(try GitHubJSON.decode(Account.self, from: Data(account.utf8)).get().kind == .unknown)
    }

    @Test("reports malformed JSON as a decoding failure")
    func malformed() {
        let result = GitHubJSON.decode(WorkflowRun.self, from: Data("[]".utf8))
        guard case .failure(.decoding) = result else {
            Issue.record("expected a decoding failure, got \(result)")
            return
        }
    }
}
