import Foundation
import Testing

@testable import RunnersKit

@Suite("Text report")
struct TextReportTests {
    let repository = Fixtures.repository("octo/app")

    var snapshot: StatusSnapshot {
        let jobs = [
            Fixtures.job(1, "lint", .completed, conclusion: .success, runner: "runner-a"),
            Fixtures.job(2, "test", .running, runner: "runner-b", step: "Run tests"),
            Fixtures.job(3, "deploy", .queued, labels: ["self-hosted", "linux"]),
            Fixtures.job(4, "audit", .completed, conclusion: .failure, runner: "runner-c"),
        ]
        return StatusSnapshot(
            provider: GitHubProvider(),
            owner: Owner(id: "1", login: "octo", kind: .user),
            repositoryCount: 12,
            runs: [
                ActiveRun(
                    repository: repository,
                    run: Fixtures.run(7, .running, minutesAgo: 5),
                    jobs: jobs
                )
            ],
            rateLimit: Fixtures.rateLimit,
            fetchedAt: Fixtures.now
        )
    }

    func lines(_ report: TextReport = TextReport(now: Fixtures.now)) -> [String] {
        report.render(snapshot).components(separatedBy: "\n")
    }

    @Test("summarizes the snapshot in the header")
    func header() {
        #expect(lines()[0].hasPrefix("octo on GitHub · 1 active run in 1 of 12 repositories · "))
    }

    @Test("describes each run")
    func run() {
        let lines = lines()
        #expect(lines.contains("octo/app"))
        #expect(lines.contains("  ● CI #7  Commit 7"))
        #expect(lines.contains("    running 5m 00s · main · push · @octo · 2/4 jobs done"))
        #expect(lines.contains("    https://example.com/runs/7"))
    }

    @Test("after a failed refresh, shows the last snapshot as it was taken, then the failure")
    func failedRefresh() {
        let later = Fixtures.now.addingTimeInterval(600)
        let lines = TextReport(now: later)
            .render(snapshot, refreshFailed: .transport("offline"), lastAttempt: later)
            .components(separatedBy: "\n")
        #expect(lines.contains("    running 5m 00s · main · push · @octo · 2/4 jobs done"))
        #expect(lines.suffix(3).first == "")
        #expect(lines.suffix(2).first == "⚠ Network error: offline")
        #expect(lines.last?.hasPrefix("Showing the runs as of ") == true)
        #expect(lines.last?.contains(" · retrying, last attempt ") == true)
    }

    @Test("paints a failed refresh yellow")
    func failedRefreshColor() {
        let lines = TextReport(style: .colored, now: Fixtures.now)
            .failedRefresh(.transport("offline"), shownAt: Fixtures.now, lastAttempt: Fixtures.now)
        #expect(lines.first == "\u{1B}[33m⚠ Network error: offline\u{1B}[0m")
    }

    @Test("shows how a finished run ended, how long it took and how long ago")
    func finished() {
        let report = TextReport(now: Fixtures.now)
        let run = Fixtures.run(8, .running, minutesAgo: 5).finished(.failure, minutesAgo: 2)
        #expect(report.state(run) == "failure in 3m 00s, 2m 00s ago")
        let lines = report.runLines(ActiveRun(repository: repository, run: run))
        #expect(lines.first == "  ✗ CI #8  Commit 8")
        #expect(report.state(run.with(completedAt: nil)) == "failure")
    }

    @Test("counts finished runs apart from active ones")
    func finishedSummary() {
        let finished = ActiveRun(
            repository: repository,
            run: Fixtures.run(8, .running).finished(.success)
        )
        #expect(
            snapshot.with(runs: snapshot.runs + [finished]).summary
                == "1 active run in 1 of 12 repositories · 1 finished"
        )
        #expect(
            snapshot.with(runs: [finished]).summary
                == "no active runs in 12 repositories · 1 finished"
        )
    }

    @Test("lists running, queued and failed jobs, aligned, and hides passed ones")
    func jobs() {
        let lines = lines()
        #expect(lines.contains("    ● test   2m 00s        runner-b → Run tests"))
        #expect(lines.contains("    ○ deploy queued 3m 00s self-hosted, linux"))
        #expect(lines.contains("    ✗ audit  1m 00s        runner-c"))
        #expect(!lines.contains { $0.contains("lint") })
    }

    @Test("lists passed jobs when asked")
    func passedJobs() {
        let lines = lines(TextReport(now: Fixtures.now, showsPassedJobs: true))
        #expect(lines.contains("    ✓ lint   1m 00s        runner-a"))
    }

    @Test("shows the remaining API quota")
    func footer() {
        #expect(
            lines().last?.hasPrefix("API quota \(4_321.formatted())/\(5_000.formatted()) · resets ")
                == true
        )
    }

    @Test("says so when nothing runs")
    func empty() {
        let empty = StatusSnapshot(
            provider: GitLabProvider(),
            owner: nil,
            repositoryCount: 3,
            runs: [],
            rateLimit: nil,
            fetchedAt: Fixtures.now
        )
        let text = TextReport(now: Fixtures.now).render(empty)
        #expect(text.hasPrefix("GitLab · no active runs in 3 projects · "))
        #expect(!text.contains("\n"))
    }

    @Test("prefixes job names with their stage")
    func stages() {
        let jobs = [
            Fixtures.job(1, "rspec 1/2", .running, stage: "test", runner: "shared-1"),
            Fixtures.job(2, "deploy", .pending, stage: "deploy", labels: ["docker"]),
        ]
        let lines = TextReport(now: Fixtures.now).jobLines(jobs)

        #expect(
            lines == [
                "    ● test › rspec 1/2 2m 00s         shared-1",
                "    ○ deploy › deploy  pending 3m 00s docker",
            ]
        )
    }

    @Test("colors only when asked")
    func colors() {
        #expect(!TextReport(style: .plain, now: Fixtures.now).render(snapshot).contains("\u{1B}["))
        #expect(
            TextReport(style: .colored, now: Fixtures.now).render(snapshot).contains(
                "\u{1B}[33m●\u{1B}[0m"
            )
        )
    }

    @Test(
        "formats durations compactly",
        arguments: [
            (0.0, "0s"), (42, "42s"), (59.6, "1m 00s"), (125, "2m 05s"),
            (3_780, "1h 03m"), (190_000, "2d 4h"), (-5, "0s"),
        ]
    )
    func elapsed(seconds: Double, expected: String) {
        #expect(Elapsed.format(seconds) == expected)
    }
}
