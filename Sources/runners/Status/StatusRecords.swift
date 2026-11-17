import ProgramStatus
import RunnersKit

/// The records `--watch` keeps on the terminal, so runs that finish can be cleared and a
/// record is sent again only when it changes.
struct StatusRecords: Sendable {
    /// The last report sent for each record on the terminal now, by id; the root's id is `nil`.
    private(set) var sent: [String?: StatusReport] = [:]

    /// The ids of the repository and run records on the terminal now.
    var ids: Set<String> { Set(sent.keys.compactMap(\.self)) }

    /// The reports that bring the terminal up to date: clears for repositories and runs that
    /// are no longer active, then the root record and one per repository and run, leaving out
    /// any the terminal already shows as they are. A failure changes only the root record.
    mutating func update(_ result: Result<StatusSnapshot, RunnersError>) -> [StatusReport] {
        switch result {
            case .success(let snapshot): update(snapshot)
            case .failure(let error): changed([.failed(error)])
        }
    }

    /// Only the root record, for a watch of runners.
    mutating func update(runners result: Result<RunnersSnapshot, RunnersError>) -> [StatusReport] {
        changed([result.match(StatusReport.watching, StatusReport.failed)])
    }

    mutating func update(_ snapshot: StatusSnapshot) -> [StatusReport] {
        let records = snapshot.byRepository.flatMap { group in
            [StatusReport.repository(group)] + group.runs.map(StatusReport.run)
        }
        let gone = ids.subtracting(records.compactMap(\.id))
        for id in gone { sent[id] = nil }
        return Self.clears(of: gone) + changed([.watching(snapshot)] + records)
    }

    /// Clears every record this watch made.
    mutating func clear() -> [StatusReport] {
        defer { sent = [:] }
        return Self.clears(of: ids)
    }

    /// The reports that differ from what was last sent for their record, remembered as sent.
    mutating func changed(_ reports: [StatusReport]) -> [StatusReport] {
        var changed: [StatusReport] = []
        for report in reports where sent[report.id] != report {
            sent[report.id] = report
            changed.append(report)
        }
        return changed
    }

    /// A clear removes a record and the ones beneath it, so a run is cleared on its own only
    /// when its repository stays.
    static func clears(of gone: Set<String>) -> [StatusReport] {
        gone.filter { id in parent(of: id).map { !gone.contains($0) } ?? true }
            .sorted()
            .map { .clear(id: $0) }
    }

    static func parent(of id: String) -> String? {
        id.firstIndex(of: "/").map { String(id[..<$0]) }
    }
}
