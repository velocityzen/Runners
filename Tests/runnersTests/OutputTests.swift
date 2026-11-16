import Foundation
import RunnersKit
import Testing

@testable import runners

@Suite("Watch screen")
struct OutputTests {
    let output = Output(json: false, colored: false, showsPassedJobs: false)
    let later = Snapshots.now.addingTimeInterval(600)

    var snapshot: StatusSnapshot {
        Snapshots.snapshot([Snapshots.active(Snapshots.repository("octo/app", id: "1"), 7)])
    }

    @Test("shows the report")
    func report() {
        let screen = output.screen(for: .success(snapshot), shown: nil, at: later)
        #expect(screen == output.report(at: later).render(snapshot))
    }

    @Test("keeps the last report, as it was taken, when a refresh fails, with the failure beneath")
    func keepsLastReport() {
        let screen = output.screen(for: .failure(.transport("offline")), shown: snapshot, at: later)
        #expect(screen.hasPrefix(output.report(at: Snapshots.now).render(snapshot) + "\n\n"))
        #expect(screen.contains("\n⚠ Network error: offline\nShowing the runs as of "))
        #expect(screen.contains(" · retrying, last attempt "))
    }

    @Test("shows only the failure before there is a report")
    func failureFirst() {
        let screen = output.screen(for: .failure(.transport("offline")), shown: nil, at: later)
        #expect(screen.hasPrefix("Network error: offline\n\nRetrying… (last attempt "))
    }
}
