import Foundation

@testable import RunnersKit

enum Fixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static let me = Account(id: 1, login: "octo", kind: .user)
    static let org = Account(id: 2, login: "acme", kind: .organization)

    static func repository(
        _ name: String,
        owner: Account = me,
        id: Int? = nil,
        isFork: Bool = false,
        isArchived: Bool = false
    ) -> Repository {
        Repository(
            id: id ?? name.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF },
            name: name,
            fullName: "\(owner.login)/\(name)",
            owner: owner,
            isFork: isFork,
            isArchived: isArchived,
            htmlURL: url("https://github.com/\(owner.login)/\(name)")
        )
    }

    static func run(
        _ id: Int,
        _ status: ActionStatus,
        name: String = "CI",
        minutesAgo: Double = 5
    ) -> WorkflowRun {
        WorkflowRun(
            id: id,
            name: name,
            displayTitle: "Commit \(id)",
            runNumber: id,
            event: "push",
            status: status,
            headBranch: "main",
            headSHA: "abc\(id)",
            htmlURL: url("https://github.com/octo/repo/actions/runs/\(id)"),
            createdAt: now.addingTimeInterval(-minutesAgo * 60),
            updatedAt: now,
            runStartedAt: now.addingTimeInterval(-minutesAgo * 60),
            actor: me
        )
    }

    static func job(
        _ id: Int,
        _ name: String,
        _ status: ActionStatus,
        conclusion: Conclusion? = nil,
        runner: String? = nil,
        labels: [String] = ["ubuntu-latest"],
        step: String? = nil
    ) -> WorkflowJob {
        WorkflowJob(
            id: id,
            runID: 1,
            name: name,
            status: status,
            conclusion: conclusion,
            createdAt: now.addingTimeInterval(-180),
            startedAt: status == .queued ? nil : now.addingTimeInterval(-120),
            completedAt: status == .completed ? now.addingTimeInterval(-60) : nil,
            labels: labels,
            runnerName: runner,
            steps: step.map { [WorkflowJob.Step(number: 1, name: $0, status: .inProgress)] }
        )
    }

    static func url(_ string: String) -> URL {
        URL(string: string) ?? URL(filePath: "/")
    }

    static let rateLimit = RateLimit(limit: 5_000, remaining: 4_321, used: 679, reset: 1_800_003_600)
}

/// Wire shapes the client reads but does not expose.
struct RunsBody: Encodable {
    let total_count: Int
    let workflow_runs: [WorkflowRun]

    init(_ runs: [WorkflowRun]) {
        total_count = runs.count
        workflow_runs = runs
    }
}

struct JobsBody: Encodable {
    let total_count: Int
    let jobs: [WorkflowJob]

    init(_ jobs: [WorkflowJob]) {
        total_count = jobs.count
        self.jobs = jobs
    }
}

struct CountBody: Encodable {
    let total_count: Int
}

struct RateLimitBody: Encodable {
    struct Resources: Encodable { let core: RateLimit }
    let resources: Resources

    init(_ core: RateLimit) {
        resources = Resources(core: core)
    }
}
