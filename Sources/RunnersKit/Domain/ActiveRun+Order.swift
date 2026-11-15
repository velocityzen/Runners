import Foundation

extension ActiveRun {
    /// One entry per run — a run that changed status between two requests can show up twice —
    /// grouped by repository name, newest run first.
    static func ordered(_ runs: [ActiveRun]) -> [ActiveRun] {
        runs.uniqued(by: \.id)
            .sorted(by: isOrderedBefore)
    }

    static func isOrderedBefore(_ lhs: ActiveRun, _ rhs: ActiveRun) -> Bool {
        switch lhs.repository.fullName.localizedStandardCompare(rhs.repository.fullName) {
            case .orderedSame: lhs.run.createdAt > rhs.run.createdAt
            case let order: order == .orderedAscending
        }
    }
}
