import Foundation
import RunnersKit

/// Domain values for status reporting tests.
enum Snapshots {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let url = URL(filePath: "/runs")

    static func repository(_ fullName: String, id: String) -> Repository {
        Repository(
            id: id,
            name: String(fullName.split(separator: "/").last ?? ""),
            fullName: fullName,
            webURL: url
        )
    }

    static func run(_ id: Int, _ status: RunStatus, title: String? = "Fix the build") -> Run {
        Run(
            id: String(id),
            name: "CI",
            title: title,
            number: id,
            status: status,
            branch: "main",
            webURL: url,
            createdAt: now
        )
    }

    static func job(_ id: Int, _ status: RunStatus) -> Job {
        Job(id: String(id), name: "job \(id)", status: status)
    }

    static func active(
        _ repository: Repository,
        _ id: Int,
        _ status: RunStatus = .running,
        jobs: [Job]? = nil
    ) -> ActiveRun {
        ActiveRun(repository: repository, run: run(id, status), jobs: jobs)
    }

    static func snapshot(_ runs: [ActiveRun], repositories: Int = 12) -> StatusSnapshot {
        StatusSnapshot(
            provider: .github,
            owner: Owner(id: "1", login: "octo", kind: .organization),
            repositoryCount: repositories,
            runs: runs,
            rateLimit: nil,
            fetchedAt: now
        )
    }
}
