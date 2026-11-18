import Foundation

// Depot CI's messages, from `depot.ci.v1` in depot/cli's `proto/depot/ci/v1/ci.proto` and
// Depot's API reference. Proto3 JSON leaves out fields that hold their default (an empty
// string, a zero, an empty list), so nearly every field is optional. Times are RFC 3339
// strings.

/// `ListRuns`: by default it gives running and queued runs; `repo` is an exact `owner/name`.
struct DepotListRuns: ConnectPagedRequest {
    var status: [String]
    var pageSize: Int
    var pageToken: String?
    var repo: String?

    func after(_ token: String) -> DepotListRuns {
        var next = self
        next.pageToken = token
        return next
    }
}

struct DepotRunsPage: ConnectPage {
    let runs: [DepotRun]?
    /// Empty on the last page.
    let nextPageToken: String?

    var items: [DepotRun] {
        runs ?? []
    }

    var nextPage: String? {
        nextPageToken
    }
}

/// A run from `ListRuns`: what started it and on which commit, but not its workflows.
struct DepotRun: Decodable, Sendable {
    /// Every status a run can have.
    static let statuses = ["queued", "running", "finished", "failed", "cancelled"]

    let runId: String
    /// `owner/name` on GitHub.
    let repo: String?
    /// `push`, `pull_request`, `workflow_dispatch`, …
    let trigger: String?
    let sha: String?
    let headSha: String?
    let ref: String?
    let status: String?
    let createdAt: String?
}

/// `GetRunStatus`
struct DepotRunStatus: Decodable, Sendable {
    let orgId: String?
    let runId: String?
    let status: String?
    let workflows: [DepotWorkflowStatus]?
}

struct DepotWorkflowStatus: Decodable, Sendable {
    let workflowId: String
    let status: String?
    /// Its YAML's `name:`, empty when it has none.
    let name: String?
    /// `.depot/workflows/ci.yml`; empty for an inline workflow.
    let workflowPath: String?
    let jobs: [DepotJobStatus]?
}

struct DepotJobStatus: Decodable, Sendable {
    let jobId: String
    /// The job's ID in its workflow: `build`.
    let jobKey: String?
    let jobDisplayName: String?
    let status: String?

    var isUnfinished: Bool {
        RunStatus(depotJob: status) != .completed
    }

    func job(webURL: URL) -> Job {
        Job(
            id: jobId,
            name: DepotJob.name(jobDisplayName, jobKey, jobId),
            status: RunStatus(depotJob: status),
            conclusion: Conclusion(depotStatus: status),
            webURL: webURL
        )
    }
}

/// `GetJob`
struct DepotJob: Decodable, Sendable {
    struct RunsOn: Decodable, Sendable {
        let labels: [String]?
        let image: String?
        let cpus: Int?
        let memoryGb: Int?

        /// `4 CPUs, 16 GB`
        var machine: String? {
            DepotMachine.describe(cpus: cpus, memoryGB: memoryGb)
        }
    }

    let jobId: String
    let jobKey: String?
    let jobDisplayName: String?
    let jobStatus: String?
    /// `success`, `failure`, `cancelled`, `skipped` or `timed_out`; empty until it ends.
    let jobConclusion: String?
    let jobCreatedAt: String?
    let jobStartedAt: String?
    let jobFinishedAt: String?
    let runsOn: RunsOn?

    func job(webURL: URL) -> Job {
        let labels = runsOn?.labels ?? []
        return Job(
            id: jobId,
            name: Self.name(jobDisplayName, jobKey, jobId),
            status: RunStatus(depotJob: jobStatus),
            conclusion: Conclusion(depot: jobConclusion) ?? Conclusion(depotStatus: jobStatus),
            createdAt: DepotTime.date(jobCreatedAt),
            startedAt: DepotTime.date(jobStartedAt),
            completedAt: DepotTime.date(jobFinishedAt),
            labels: labels.isEmpty ? [runsOn?.image].compact() : labels,
            runner: runsOn?.machine,
            webURL: webURL
        )
    }

    /// The display name, else the key, else the ID: the first that isn't empty.
    static func name(_ candidates: String?...) -> String {
        candidates.compact().first { !$0.isEmpty } ?? "job"
    }
}

/// `GetWorkflow`: the workflow, the run it is part of, and its jobs with their times.
struct DepotWorkflow: Decodable, Sendable {
    struct Execution: Decodable, Sendable {
        let execution: Int?
        let jobs: [DepotWorkflowJob]?
    }

    let orgId: String?
    let runId: String?
    let repo: String?
    let ref: String?
    let sha: String?
    let headSha: String?
    let trigger: String?
    let runCreatedAt: String?
    let workflowId: String
    let workflowName: String?
    let workflowPath: String?
    let workflowStatus: String?
    let workflowCreatedAt: String?
    let workflowStartedAt: String?
    let workflowFinishedAt: String?
    /// depot/cli's proto has the jobs here; Depot's API reference has them in each execution.
    let jobs: [DepotWorkflowJob]?
    /// One per re-run of the workflow.
    let executions: [Execution]?

    /// The jobs of the latest execution.
    var latestJobs: [DepotWorkflowJob] {
        jobs
            ?? executions?.max { ($0.execution ?? 0) < ($1.execution ?? 0) }?.jobs
            ?? []
    }

    var workflowRun: DepotWorkflowRun {
        DepotWorkflowRun(
            orgID: orgId,
            workflowID: workflowId,
            name: workflowName,
            path: workflowPath,
            status: workflowStatus,
            trigger: trigger,
            ref: ref,
            commit: [headSha, sha].compact().first { !$0.isEmpty },
            createdAt: DepotTime.date(workflowCreatedAt) ?? DepotTime.date(runCreatedAt),
            startedAt: DepotTime.date(workflowStartedAt),
            finishedAt: DepotTime.date(workflowFinishedAt)
        )
    }
}

/// A job as `GetWorkflow` gives it: its status and times.
struct DepotWorkflowJob: Decodable, Sendable {
    let jobId: String
    let jobKey: String?
    let jobDisplayName: String?
    let status: String?
    let startedAt: String?
    let finishedAt: String?

    func job(webURL: URL) -> Job {
        Job(
            id: jobId,
            name: DepotJob.name(jobDisplayName, jobKey, jobId),
            status: RunStatus(depotJob: status),
            conclusion: Conclusion(depotStatus: status),
            startedAt: DepotTime.date(startedAt),
            completedAt: DepotTime.date(finishedAt),
            webURL: webURL
        )
    }
}

/// A workflow of a Depot run, with what `runners` shows of it as a run.
struct DepotWorkflowRun: Sendable {
    let orgID: String?
    let workflowID: String
    let name: String?
    let path: String?
    let status: String?
    let trigger: String?
    let ref: String?
    let commit: String?
    let createdAt: Date?
    let startedAt: Date?
    let finishedAt: Date?

    init(
        orgID: String?,
        workflowID: String,
        name: String?,
        path: String?,
        status: String?,
        trigger: String?,
        ref: String?,
        commit: String?,
        createdAt: Date?,
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.orgID = orgID
        self.workflowID = workflowID
        self.name = name
        self.path = path
        self.status = status
        self.trigger = trigger
        self.ref = ref
        self.commit = commit
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    /// A workflow as `GetRunStatus` gives it, with the run `ListRuns` gave.
    init(_ workflow: DepotWorkflowStatus, of run: DepotRun, orgID: String?) {
        self.init(
            orgID: orgID,
            workflowID: workflow.workflowId,
            name: workflow.name,
            path: workflow.workflowPath,
            status: workflow.status,
            trigger: run.trigger,
            ref: run.ref,
            commit: [run.headSha, run.sha].compact().first { !$0.isEmpty },
            createdAt: DepotTime.date(run.createdAt)
        )
    }

    /// `https://depot.dev/orgs/{org}/workflows/{workflow}`, as the depot CLI links it.
    var webURL: URL {
        let site = URL(string: "https://depot.dev") ?? URL(filePath: "/")
        guard let orgID, !orgID.isEmpty else { return site }
        return site.appending(path: "orgs/\(orgID)/workflows/\(workflowID)")
    }

    /// Its `name:`, else its file's name, as GitHub names a workflow without one.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let path, !path.isEmpty { return URL(filePath: path).lastPathComponent }
        return "Depot CI"
    }

    /// `main` for `refs/heads/main`; any other ref as it is.
    var branch: String? {
        guard let ref, !ref.isEmpty else { return nil }
        return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
    }

    var run: Run {
        Run(
            id: workflowID,
            name: displayName,
            trigger: trigger.flatMap { $0.isEmpty ? nil : $0 },
            status: RunStatus(depotRun: status),
            conclusion: Conclusion(depotStatus: status),
            branch: branch,
            commit: commit,
            webURL: webURL,
            createdAt: createdAt ?? startedAt ?? .distantPast,
            startedAt: startedAt,
            completedAt: finishedAt
        )
    }
}

/// The machine a job asks Depot for.
enum DepotMachine {
    /// `4 CPUs, 16 GB`; nil when it names neither. A zero is a size not asked for.
    static func describe(cpus: Int?, memoryGB: Int?) -> String? {
        let parts = [
            cpus.flatMap { $0 > 0 ? $0 : nil }.map { $0 == 1 ? "1 CPU" : "\($0) CPUs" },
            memoryGB.flatMap { $0 > 0 ? $0 : nil }.map { "\($0) GB" },
        ]
        .compact()
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Depot's times: RFC 3339, with or without fractions of a second; empty or absent while
/// what they mark hasn't happened.
enum DepotTime {
    static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return JSONCoding.parseDate(raw)
    }
}

extension Repository {
    /// A GitHub repository Depot CI runs for, by its `owner/name`.
    init(depot fullName: String) {
        self.init(
            id: fullName,
            name: String(fullName.split(separator: "/").last ?? Substring(fullName)),
            fullName: fullName,
            webURL: URL(string: "https://github.com/\(fullName)")
                ?? URL(string: "https://github.com") ?? URL(filePath: "/")
        )
    }
}
