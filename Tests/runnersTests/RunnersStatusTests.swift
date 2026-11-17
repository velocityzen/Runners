import Foundation
import ProgramStatus
import RunnersKit
import Testing

@testable import runners

@Suite("Runners on the terminal")
struct RunnersStatusTests {
    func snapshot(busy: Bool) -> RunnersSnapshot {
        RunnersSnapshot(
            provider: GitHubProvider(),
            listing: RunnerListing(
                owner: Owner(id: "2", login: "acme", kind: .organization),
                runners: [
                    Runner(id: "1", name: "box", kind: .selfHosted, status: .online, busy: busy)
                ]
            ),
            rateLimit: nil,
            fetchedAt: Snapshots.now
        )
    }

    @Test("reports a check of runners as working, then done or failed")
    func check() {
        #expect(
            StatusReport.checkingRunners(GitHubProvider()) == .working("Checking runners on GitHub")
        )
        #expect(
            StatusReport.checkedRunners(.success(snapshot(busy: true)))
                == .done("acme on GitHub: 1 runner, 1 busy")
        )
        #expect(StatusReport.checkedRunners(.failure(.unauthorized("bad"))).state == .error)
    }

    @Test("is working while a runner is busy and idle otherwise, with only the root record")
    func watching() {
        var records = StatusRecords()
        #expect(
            records.update(runners: .success(snapshot(busy: true))).map(\.state) == [.working()]
        )
        #expect(records.update(runners: .success(snapshot(busy: true))).isEmpty)
        #expect(
            records.update(runners: .success(snapshot(busy: false)))
                == [.idle("acme on GitHub: 1 runner")]
        )
        #expect(records.update(runners: .failure(.transport("offline"))).map(\.state) == [.error])
        #expect(records.ids.isEmpty)
    }

    @Test("keeps the last runners on screen when a refresh fails")
    func screen() {
        let output = Output(json: false, colored: false, showsPassedJobs: false)
        let later = Snapshots.now.addingTimeInterval(60)
        let screen = output.screen(
            forRunners: .failure(.transport("offline")),
            shown: snapshot(busy: false),
            at: later
        )
        #expect(screen.contains("Idle\n  ○ box"))
        #expect(screen.contains("⚠ Network error: offline"))
        #expect(screen.contains("Showing the runners as of"))
    }
}
