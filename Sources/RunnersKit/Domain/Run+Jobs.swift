import FP
import Foundation

// A GitHub workflow run as a runner vendor knows it: by the jobs of it that ran on the
// vendor's machines, which is all Depot's and Namespace's APIs report.

extension Repository {
    /// A GitHub repository a vendor runs jobs for, by its `owner/name`.
    init(gitHubFullName fullName: String, isPrivate: Bool = false) {
        self.init(
            id: fullName,
            name: String(fullName.split(separator: "/").last ?? Substring(fullName)),
            fullName: fullName,
            webURL: URL(string: "https://github.com/\(fullName)")
                ?? URL(string: "https://github.com") ?? URL(filePath: "/"),
            isPrivate: isPrivate
        )
    }
}

/// The size of the machine a job asked for.
enum MachineSize {
    /// `4 CPUs, 16 GB`; nil when it names neither. A zero is a size not asked for, and a
    /// fraction of a gigabyte shows to one place: `1.5 GB`.
    static func describe(cpus: Int?, memoryGB: Double?) -> String? {
        let parts = [
            cpus.flatMap { $0 > 0 ? $0 : nil }.map { $0 == 1 ? "1 CPU" : "\($0) CPUs" },
            memoryGB.flatMap { $0 > 0 ? $0 : nil }.map { gigabytes in
                gigabytes == gigabytes.rounded()
                    ? "\(Int(gigabytes)) GB"
                    : "\((gigabytes * 10).rounded() / 10) GB"
            },
        ]
        .compact()
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

extension RunStatus {
    /// A run's status from its jobs': completed once every job is; else running while any
    /// runs, then queued, waiting or pending while any is.
    static func summing(_ jobs: [Job]) -> RunStatus {
        let statuses = jobs.map(\.status)
        if !statuses.isEmpty, statuses.allSatisfy({ $0 == .completed }) { return .completed }
        return [.running, .queued, .waiting, .pending].first(where: statuses.contains)
            ?? .unknown
    }
}

extension Conclusion {
    /// How a run ended, from its jobs: a failure if any failed, else cancelled if any was; a
    /// success once every job passed, or skipped when every job was. Nil until every job has
    /// finished.
    static func summing(_ jobs: [Job]) -> Conclusion? {
        guard RunStatus.summing(jobs) == .completed else { return nil }
        let conclusions = jobs.map { $0.conclusion ?? .unknown }
        if conclusions.contains(where: \.isFailure) { return .failure }
        if conclusions.contains(.cancelled) { return .cancelled }
        if !conclusions.allSatisfy(\.hasPassed) { return .unknown }
        return conclusions.allSatisfy { $0 == .skipped } ? .skipped : .success
    }
}

extension Run {
    /// A run's page on GitHub: the page of one of its jobs, `…/actions/runs/1/job/2`, without
    /// the job; else `https://github.com/{repository}/actions/runs/{id}`.
    static func gitHubPage(jobPages: [String], repository: String, runID: String) -> URL {
        let fromJob = jobPages.lazy.compactMap { page -> URL? in
            guard let range = page.range(of: "/job/") else { return nil }
            return URL(string: String(page[..<range.lowerBound]))
        }
        .first
        return fromJob
            ?? URL(string: "https://github.com/\(repository)/actions/runs/\(runID)")
            ?? URL(filePath: "/")
    }
}

extension Array {
    /// The newest attempt of each job, oldest first, ties in the order given: a re-run job
    /// keeps its name and gets a new ID.
    func newestAttempts(name: (Element) -> String, created: (Element) -> Date?) -> [Element] {
        let oldestFirst = enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (created(lhs.element), created(rhs.element))
                return left == right
                    ? lhs.offset < rhs.offset : (left ?? .distantPast) < (right ?? .distantPast)
            }
            .map(\.element)
        return Array(oldestFirst.reversed()).uniqued(by: name).reversed()
    }

    /// The elements grouped by key, each group in order, the groups in the order their first
    /// elements come. Elements without a key are left out.
    func grouped<Key: Hashable>(by key: (Element) -> Key?) -> [[Element]] {
        let keyed = compactMap { element in key(element).map { (key: $0, element: element) } }
        let byKey = Dictionary(grouping: keyed, by: \.key)
        return keyed.map(\.key).uniqued(by: \.self).compactMap { byKey[$0]?.map(\.element) }
    }
}
