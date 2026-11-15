import ProgramStatus
import RunnersKit

/// The records `--watch` keeps on the terminal, so runs that finish can be cleared.
struct StatusRecords: Sendable {
    /// The ids of the repository and run records on the terminal now.
    private(set) var ids: Set<String> = []

    /// The reports that bring the terminal up to date: clears for repositories and runs that
    /// are no longer active, then the root record and one per repository and run. A failure
    /// changes only the root record.
    mutating func update(_ result: Result<StatusSnapshot, RunnersError>) -> [StatusReport] {
        switch result {
            case .success(let snapshot): update(snapshot)
            case .failure(let error): [.failed(error)]
        }
    }

    mutating func update(_ snapshot: StatusSnapshot) -> [StatusReport] {
        let records = snapshot.byRepository.flatMap { group in
            [StatusReport.repository(group)] + group.runs.map(StatusReport.run)
        }
        let current = Set(records.compactMap(\.id))
        let clears = Self.clears(of: ids.subtracting(current))
        ids = current
        return clears + [.watching(snapshot)] + records
    }

    /// Clears every record this watch made.
    mutating func clear() -> [StatusReport] {
        defer { ids = [] }
        return Self.clears(of: ids)
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
