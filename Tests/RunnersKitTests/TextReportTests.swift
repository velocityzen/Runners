import Foundation
import Testing

@testable import RunnersKit

@Suite("Text report")
struct TextReportTests {
    let repository = Fixtures.repository("app")

    var snapshot: StatusSnapshot {
        let jobs = [
            Fixtures.job(1, "lint", .completed, conclusion: .success, runner: "runner-a"),
            Fixtures.job(2, "test", .inProgress, runner: "runner-b", step: "Run tests"),
            Fixtures.job(3, "deploy", .queued, labels: ["self-hosted", "linux"]),
            Fixtures.job(4, "audit", .completed, conclusion: .failure, runner: "runner-c"),
        ]
        return StatusSnapshot(
            owner: Fixtures.me,
            repositoryCount: 12,
            runs: [ActiveRun(repository: repository, run: Fixtures.run(7, .inProgress, minutesAgo: 5), jobs: jobs)],
            rateLimit: Fixtures.rateLimit,
            fetchedAt: Fixtures.now
        )
    }

    func lines(_ report: TextReport = TextReport(now: Fixtures.now)) -> [String] {
        report.render(snapshot).components(separatedBy: "\n")
    }

    @Test("summarizes the snapshot in the header")
    func header() {
        #expect(lines()[0].hasPrefix("octo · 1 active run in 1 of 12 repositories · "))
    }

    @Test("describes each run")
    func run() {
        let lines = lines()
        #expect(lines.contains("octo/app"))
        #expect(lines.contains("  ● CI #7  Commit 7"))
        #expect(lines.contains("    running 5m 00s · main · push · @octo · 2/4 jobs done"))
        #expect(lines.contains("    https://github.com/octo/repo/actions/runs/7"))
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
        #expect(lines().last?.hasPrefix("API quota \(4_321.formatted())/\(5_000.formatted()) · resets ") == true)
    }

    @Test("says so when nothing runs")
    func empty() {
        let empty = StatusSnapshot(owner: nil, repositoryCount: 3, runs: [], rateLimit: nil, fetchedAt: Fixtures.now)
        let text = TextReport(now: Fixtures.now).render(empty)
        #expect(text.hasPrefix("no active runs in 3 repositories · "))
        #expect(!text.contains("\n"))
    }

    @Test("colors only when asked")
    func colors() {
        #expect(!TextReport(style: .plain, now: Fixtures.now).render(snapshot).contains("\u{1B}["))
        #expect(TextReport(style: .colored, now: Fixtures.now).render(snapshot).contains("\u{1B}[33m●\u{1B}[0m"))
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
