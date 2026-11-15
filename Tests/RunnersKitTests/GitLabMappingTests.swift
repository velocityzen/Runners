import Foundation
import Testing

@testable import RunnersKit

@Suite("GitLab mapping")
struct GitLabMappingTests {
    @Test("reads a job with its stage, runner, pipeline and commit")
    func job() throws {
        let json = """
            {
              "id": 8, "status": "running", "stage": "test", "name": "rspec 1/4", "ref": "main",
              "tag": false, "coverage": null, "allow_failure": false,
              "created_at": "2026-11-15T15:00:00.123Z", "started_at": "2026-11-15T15:01:00.456Z",
              "finished_at": null, "duration": 61.2, "queued_duration": 60.3,
              "user": { "id": 1, "username": "octo", "name": "Octo", "state": "active" },
              "commit": { "id": "0a1b2c", "short_id": "0a1b2c", "title": "Fix it" },
              "pipeline": { "id": 6, "project_id": 1, "ref": "main", "sha": "0a1b2c", "status": "running" },
              "web_url": "https://gitlab.com/acme/api/-/jobs/8",
              "runner": { "id": 32, "description": "shared-runners-manager-1", "is_shared": true, "runner_type": "instance_type" },
              "tag_list": ["docker", "linux"]
            }
            """
        let raw = try JSONCoding.decode(GitLabJob.self, from: Data(json.utf8)).get()
        let job = raw.job

        #expect(job.id == "8")
        #expect(job.stage == "test")
        #expect(job.status == .running)
        #expect(job.conclusion == nil)
        #expect(job.runner == "shared-runners-manager-1")
        #expect(job.labels == ["docker", "linux"])
        #expect(abs((job.startedAt?.timeIntervalSince1970 ?? 0) - 1_794_754_860.456) < 0.001)
        #expect(raw.pipeline == .init(id: 6, status: "running"))
        #expect(raw.commit?.title == "Fix it")
    }

    @Test("reads a pipeline; the title comes from elsewhere")
    func pipeline() throws {
        let json = """
            {
              "id": 6, "iid": 42, "project_id": 1, "name": null, "sha": "0a1b2c", "ref": "main",
              "status": "pending", "source": "merge_request_event",
              "created_at": "2026-11-15T15:00:00.000Z", "updated_at": "2026-11-15T15:00:05.000Z",
              "started_at": null, "finished_at": null,
              "web_url": "https://gitlab.com/acme/api/-/pipelines/6",
              "user": { "id": 1, "username": "octo" }
            }
            """
        let run = try JSONCoding.decode(GitLabPipeline.self, from: Data(json.utf8)).get()
            .run(title: "Fix it", actor: "someone")

        #expect(run.name == "Pipeline")
        #expect(run.number == 42)
        #expect(run.title == "Fix it")
        #expect(run.trigger == "merge_request_event")
        #expect(run.status == .queued)
        #expect(run.actor == "octo")
    }

    @Test(
        "maps GitLab statuses",
        arguments: [
            ("created", RunStatus.pending), ("waiting_for_resource", .pending),
            ("preparing", .pending),
            ("pending", .queued), ("running", .running), ("canceling", .running),
            ("manual", .waiting),
            ("scheduled", .waiting), ("success", .completed), ("failed", .completed),
            ("canceled", .completed),
            ("skipped", .completed), ("hibernating", .unknown),
        ]
    )
    func statuses(raw: String, status: RunStatus) {
        #expect(RunStatus(gitLab: raw) == status)
    }

    @Test("takes the conclusion from finished statuses only")
    func conclusions() {
        #expect(Conclusion(gitLab: "success") == .success)
        #expect(Conclusion(gitLab: "failed") == .failure)
        #expect(Conclusion(gitLab: "canceled") == .cancelled)
        #expect(Conclusion(gitLab: "skipped") == .skipped)
        #expect(Conclusion(gitLab: "running") == nil)
    }

    @Test("leaves out projects that cannot run pipelines")
    func projects() {
        #expect(GitLabFixtures.project("a/ok", id: 1).canRunPipelines(includingForks: false))
        #expect(
            !GitLabFixtures.project("a/old", id: 2, archived: true).canRunPipelines(
                includingForks: false
            )
        )
        #expect(
            !GitLabFixtures.project("a/off", id: 3, builds: "disabled").canRunPipelines(
                includingForks: false
            )
        )
        #expect(
            !GitLabFixtures.project("a/fork", id: 4, isFork: true).canRunPipelines(
                includingForks: false
            )
        )
        #expect(
            GitLabFixtures.project("a/fork", id: 4, isFork: true).canRunPipelines(
                includingForks: true
            )
        )
    }

    @Test("finds each unfinished pipeline once, through its jobs")
    func activePipelines() {
        let repository = Fixtures.repository("acme/api", id: "1")
        let jobs = [
            GitLabFixtures.job(1, "rspec", "running", pipeline: 10),
            GitLabFixtures.job(2, "lint", "pending", pipeline: 10),
            GitLabFixtures.job(3, "deploy", "created", pipeline: 11, pipelineStatus: "manual"),
            GitLabFixtures.job(4, "stale", "created", pipeline: 12, pipelineStatus: "success"),
        ]
        let pipelines = GitLabActivePipeline.from(jobs, in: repository)

        #expect(pipelines.map(\.id) == [10, 11])
        #expect(pipelines.map(\.status) == [.running, .waiting])
        #expect(pipelines.first?.title == "Commit for 10")
        #expect(pipelines.first?.actor == "octo")
    }

    @Test("builds API URLs from hosts")
    func apiURLs() {
        #expect(GitLabService.defaultBaseURL.absoluteString == "https://gitlab.com/api/v4")
        #expect(
            GitLabService.apiURL(forHost: "gitlab.example.com")?.absoluteString
                == "https://gitlab.example.com/api/v4"
        )
        #expect(
            GitLabService.apiURL(forHost: "http://localhost:8080")?.absoluteString
                == "http://localhost:8080/api/v4"
        )
    }
}
