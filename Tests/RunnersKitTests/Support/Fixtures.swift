import Foundation

@testable import RunnersKit

enum Fixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func minutesAgo(_ minutes: Double) -> Date {
        now.addingTimeInterval(-minutes * 60)
    }

    static func url(_ string: String) -> URL {
        URL(string: string) ?? URL(filePath: "/")
    }

    // MARK: - Domain

    static func repository(_ fullName: String, id: String? = nil) -> Repository {
        Repository(
            id: id ?? fullName,
            name: String(fullName.split(separator: "/").last ?? ""),
            fullName: fullName,
            webURL: url("https://example.com/\(fullName)")
        )
    }

    static func run(_ id: Int, _ status: RunStatus, minutesAgo minutes: Double = 5) -> Run {
        Run(
            id: String(id),
            name: "CI",
            title: "Commit \(id)",
            number: id,
            trigger: "push",
            status: status,
            branch: "main",
            webURL: url("https://example.com/runs/\(id)"),
            createdAt: minutesAgo(minutes),
            startedAt: minutesAgo(minutes),
            actor: "octo"
        )
    }

    static func job(
        _ id: Int,
        _ name: String,
        _ status: RunStatus,
        conclusion: Conclusion? = nil,
        stage: String? = nil,
        runner: String? = nil,
        labels: [String] = ["ubuntu-latest"],
        step: String? = nil
    ) -> Job {
        Job(
            id: String(id),
            name: name,
            stage: stage,
            status: status,
            conclusion: conclusion,
            createdAt: minutesAgo(3),
            startedAt: status == .queued ? nil : minutesAgo(2),
            completedAt: status == .completed ? minutesAgo(1) : nil,
            labels: labels,
            runner: runner,
            currentStep: step
        )
    }

    static let rateLimit = RateLimit(
        limit: 5_000,
        remaining: 4_321,
        resetAt: now.addingTimeInterval(3_600)
    )
}
