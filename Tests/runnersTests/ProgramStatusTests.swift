import ProgramStatus
import RunnersKit
import Testing

@testable import runners

@Suite("Program status reports")
struct ProgramStatusTests {
    let app = Snapshots.repository("octo/app", id: "101")
    let web = Snapshots.repository("octo/web", id: "102")

    @Test("reports a one-off check as working, then done or failed")
    func check() {
        #expect(StatusReport.checking(GitLabProvider()) == .working("Checking CI runs on GitLab"))
        let snapshot = Snapshots.snapshot([Snapshots.active(app, 7)])
        #expect(
            StatusReport.checked(.success(snapshot))
                == .done("octo on GitHub: 1 active run in 1 of 12 repositories")
        )
        #expect(StatusReport.checked(.failure(.unauthorized("bad token"))).state == .error)
    }

    @Test("puts a multi-line error on one line")
    func error() throws {
        let report = StatusReport.failed(.server(status: 502, message: "Bad\nGateway"))
        let message = try #require(report.message)
        #expect(!message.contains("\n"))
    }

    @Test("is idle with no runs, working with runs, blocked while one waits for approval")
    func watching() {
        #expect(
            StatusReport.watching(Snapshots.snapshot([]))
                == .idle("octo on GitHub: no active runs in 12 repositories")
        )
        #expect(
            StatusReport.watching(Snapshots.snapshot([Snapshots.active(app, 7)])).state
                == .working()
        )
        let waiting = Snapshots.snapshot([
            Snapshots.active(app, 7), Snapshots.active(web, 8, .waiting),
        ])
        #expect(StatusReport.watching(waiting).state == .blocked(kind: .permission))
    }

    @Test("gives each repository a record titled with its name")
    func repository() throws {
        let snapshot = Snapshots.snapshot([
            Snapshots.active(app, 7), Snapshots.active(app, 8, .waiting),
        ])
        let group = try #require(snapshot.byRepository.first)
        #expect(
            StatusReport.repository(group)
                == .blocked("1 of 2 waiting", kind: .permission, id: "101", title: "octo/app")
        )
    }

    @Test("gives each run a record beneath its repository, with its jobs as progress")
    func run() {
        let jobs = [
            Snapshots.job(1, .completed), Snapshots.job(2, .running), Snapshots.job(3, .queued),
            Snapshots.job(4, .completed),
        ]
        let report = StatusReport.run(Snapshots.active(app, 7, jobs: jobs))
        #expect(report.id == "101/7")
        #expect(report.title == "CI #7")
        #expect(report.message == "running · main · Fix the build")
        #expect(report.state == .working(progress: 50))
    }

    @Test(
        "maps run statuses to states",
        arguments: [
            (RunStatus.running, StatusReport.State.working()),
            (.queued, .working()),
            (.pending, .working()),
            (.waiting, .blocked(kind: .permission)),
        ]
    )
    func states(status: RunStatus, state: StatusReport.State) {
        #expect(StatusReport.state(Snapshots.active(app, 7, status)) == state)
    }

    @Test(
        "maps how a finished run ended to a state",
        arguments: [
            (Conclusion.success, StatusReport.State.done),
            (.skipped, .done),
            (.failure, .error),
            (.timedOut, .error),
            (.cancelled, .idle),
            (.actionRequired, .blocked(kind: .permission)),
        ]
    )
    func finished(conclusion: Conclusion, state: StatusReport.State) {
        #expect(StatusReport.state(Snapshots.finished(app, 7, conclusion)) == state)
    }

    @Test("keeps how a finished run ended in its record")
    func finishedRun() {
        let report = StatusReport.run(Snapshots.finished(app, 7, .timedOut))
        #expect(report.message == "timed out · main · Fix the build")
        #expect(report.state == .error)
    }

    @Test("counts finished runs in the repository record, and fails it when one failed")
    func finishedRepository() throws {
        let runs = [
            Snapshots.active(app, 7), Snapshots.finished(app, 8, .failure),
            Snapshots.finished(app, 9, .success),
        ]
        let working = try #require(Snapshots.snapshot(runs).byRepository.first)
        #expect(
            StatusReport.repository(working)
                == .working("1 active · 1 failed · 1 finished", id: "101", title: "octo/app")
        )
        let ended = try #require(Snapshots.snapshot(Array(runs.dropFirst())).byRepository.first)
        #expect(
            StatusReport.repository(ended)
                == .error("1 failed · 1 finished", id: "101", title: "octo/app")
        )
        let passed = try #require(Snapshots.snapshot([runs[2]]).byRepository.first)
        #expect(
            StatusReport.repository(passed) == .done("1 finished", id: "101", title: "octo/app")
        )
    }

    @Test("is idle when only finished runs are on show")
    func onlyFinished() {
        let snapshot = Snapshots.snapshot([Snapshots.finished(app, 7, .success)])
        #expect(
            StatusReport.watching(snapshot)
                == .idle("octo on GitHub: no active runs in 12 repositories · 1 finished")
        )
    }

    @Test(
        "makes record ids out of any id",
        arguments: [("octo/app", "octo_app"), ("", "_"), ("ünï", "_n_")]
    )
    func segments(id: String, segment: String) {
        #expect(StatusReport.segment(id) == segment)
        #expect(StatusReport.segment(String(repeating: "9", count: 40)).count == 32)
    }

    @Test("cuts text to the byte limit on a character")
    func fitted() {
        #expect(StatusReport.fitted("héllo", bytes: 2) == "h")
        #expect(StatusReport.fitted("héllo", bytes: 3) == "hé")
        #expect(StatusReport.fitted("a\nb", bytes: 10) == "a b")
    }

    @Test("encodes every report it makes")
    func valid() {
        let snapshot = Snapshots.snapshot([
            Snapshots.active(Snapshots.repository("octo/app", id: "octo/app"), 7, .waiting),
            Snapshots.active(web, 8, jobs: [Snapshots.job(1, .running)]),
            Snapshots.finished(web, 9, .actionRequired),
        ])
        var records = StatusRecords()
        let reports = records.update(.success(snapshot)) + [.checked(.success(snapshot)), .stopped]
        for report in reports {
            #expect(StatusEncoder.encode(report, terminator: .st).isSuccess)
        }
    }
}
