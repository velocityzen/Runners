import ProgramStatus
import RunnersKit
import Testing

@testable import runners

@Suite("Status records")
struct StatusRecordsTests {
    let app = Snapshots.repository("octo/app", id: "101")
    let web = Snapshots.repository("octo/web", id: "102")

    @Test("reports the root, then each repository with its runs")
    func first() {
        var records = StatusRecords()
        let reports = records.update(
            .success(Snapshots.snapshot([Snapshots.active(app, 7), Snapshots.active(web, 8)]))
        )
        #expect(reports.map(\.id) == [nil, "101", "101/7", "102", "102/8"])
        #expect(records.ids == ["101", "101/7", "102", "102/8"])
    }

    @Test("clears a finished run, or its whole repository when none is left")
    func finished() {
        var records = StatusRecords()
        _ = records.update(
            .success(
                Snapshots.snapshot([
                    Snapshots.active(app, 7), Snapshots.active(app, 9), Snapshots.active(web, 8),
                ])
            )
        )
        let reports = records.update(.success(Snapshots.snapshot([Snapshots.active(app, 9)])))
        #expect(reports.filter { $0.state == .clear }.map(\.id) == ["101/7", "102"])
        #expect(records.ids == ["101", "101/9"])
    }

    @Test("changes only the root record on a failure")
    func failure() {
        var records = StatusRecords()
        _ = records.update(.success(Snapshots.snapshot([Snapshots.active(app, 7)])))
        let reports = records.update(.failure(.server(status: 500, message: "")))
        #expect(reports.map(\.id) == [nil])
        #expect(reports.first?.state == .error)
        #expect(records.ids == ["101", "101/7"])
    }

    @Test("clears every record it made, repositories only")
    func clear() {
        var records = StatusRecords()
        _ = records.update(
            .success(Snapshots.snapshot([Snapshots.active(app, 7), Snapshots.active(web, 8)]))
        )
        #expect(records.clear() == [.clear(id: "101"), .clear(id: "102")])
        #expect(records.ids.isEmpty)
        #expect(records.clear().isEmpty)
    }
}
