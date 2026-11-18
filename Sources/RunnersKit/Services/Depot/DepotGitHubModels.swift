import FP
import Foundation

// `depot.core.v1.GithubActionsService`'s messages, from depot/proto's
// `proto/depot/core/v1/github_actions.proto`. Enums come by name,
// `GITHUB_ACTIONS_JOB_STATUS_RUNNING`; 64-bit integers as strings; times in RFC 3339. A field
// at its default, an empty string or a zero, is left out.

/// `ListGithubActionsJobs`: newest first, from the last 30 days. An empty filter takes
/// everything: every connected repository, every status.
struct DepotListGitHubJobs: ConnectPagedRequest {
    /// The most jobs a page holds.
    static let pageSize = 250

    var repositories: [String]?
    var statuses: [String]?
    /// Matched against job and workflow names, and exactly against GitHub job and run IDs.
    var query: String?
    var pageSize = Self.pageSize
    var pageToken: String?

    func after(_ token: String) -> DepotListGitHubJobs {
        var next = self
        next.pageToken = token
        return next
    }
}

struct DepotGitHubJobsPage: ConnectPage {
    let jobs: [DepotGitHubJob]?
    let nextPageToken: String?

    var items: [DepotGitHubJob] {
        jobs ?? []
    }

    var nextPage: String? {
        nextPageToken
    }
}

/// A GitHub Actions job Depot ran, or will run, on one of its machines.
struct DepotGitHubJob: Decodable, Sendable, Hashable {
    static let queued = "GITHUB_ACTIONS_JOB_STATUS_QUEUED"
    static let waiting = "GITHUB_ACTIONS_JOB_STATUS_WAITING"
    static let running = "GITHUB_ACTIONS_JOB_STATUS_RUNNING"
    static let finished = "GITHUB_ACTIONS_JOB_STATUS_FINISHED"

    /// GitHub's job ID.
    let jobId: String
    /// GitHub's workflow run ID.
    let runId: String?
    /// `owner/name`
    let repository: String?
    let name: String?
    let workflowName: String?
    let workflowPath: String?
    let status: String?
    /// Unset until it finishes.
    let conclusion: String?
    /// The `runs-on` label: `depot-ubuntu-24.04-8`.
    let runnerLabel: String?
    let requestedOs: String?
    let requestedArchitecture: String?
    /// Zero, so left out, when the label names no size.
    let requestedCpuCount: Int?
    let requestedMemoryGib: Int?
    /// `https://github.com/octo/app/actions/runs/1/job/2`
    let githubUrl: String?
    /// When Depot got the job.
    let createdAt: String?
    let startedAt: String?
    let finishedAt: String?
    /// How long it waited for a machine; zero until Depot knows.
    let queueSeconds: ProtoInt64?

    var runStatus: RunStatus {
        RunStatus(depotGitHub: status)
    }

    var created: Date? {
        ProtoTime.date(createdAt)
    }

    /// The machine it asked for, and how long it waited for one: `depot-ubuntu-24.04-4,
    /// 4 CPUs, 16 GB, 12s in queue`.
    var runner: String? {
        let queued = (queueSeconds?.value ?? 0) > 0
        let parts = [
            runnerLabel.flatMap { $0.isEmpty ? nil : $0 },
            MachineSize.describe(
                cpus: requestedCpuCount,
                memoryGB: requestedMemoryGib.map(Double.init)
            ),
            queued
                ? queueSeconds.map { "\(Elapsed.format(TimeInterval($0.value))) in queue" } : nil,
        ]
        .compact()
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var job: Job {
        let status = runStatus
        return Job(
            id: jobId,
            name: DepotJob.name(name, jobId),
            status: status,
            conclusion: status == .completed ? Conclusion(depotGitHub: conclusion) : nil,
            createdAt: created,
            startedAt: ProtoTime.date(startedAt),
            completedAt: ProtoTime.date(finishedAt),
            labels: [runnerLabel].compact().filter { !$0.isEmpty },
            runner: runner,
            webURL: githubUrl.flatMap(URL.init(string:))
        )
    }
}

/// A GitHub workflow run, as far as Depot knows it: by the jobs of it that ran on Depot's
/// machines. Its other jobs, on GitHub's own runners or not yet started, are GitHub's to tell.
struct DepotGitHubRun: Sendable {
    let id: String
    let repository: String
    /// The newest attempt of each job, as a re-run gives a job a new ID in the same run,
    /// oldest first.
    let jobs: [DepotGitHubJob]

    init(id: String, repository: String, jobs: [DepotGitHubJob]) {
        self.id = id
        self.repository = repository
        self.jobs = jobs.newestAttempts(name: { $0.name ?? $0.jobId }, created: \.created)
    }

    /// The runs these jobs belong to, in the order their first jobs come.
    static func runs(of jobs: [DepotGitHubJob]) -> [DepotGitHubRun] {
        jobs.grouped { job -> String? in
            guard let runId = job.runId, !runId.isEmpty, let repository = job.repository else {
                return nil
            }
            return "\(repository.lowercased())/\(runId)"
        }
        .compactMap { jobs in
            guard let runId = jobs.first?.runId, let repository = jobs.first?.repository else {
                return nil
            }
            return DepotGitHubRun(id: runId, repository: repository, jobs: jobs)
        }
    }

    /// The workflow's `name:`, else its file's name.
    var name: String {
        let first = jobs.first
        if let name = first?.workflowName, !name.isEmpty { return name }
        if let path = first?.workflowPath, !path.isEmpty {
            return URL(filePath: path).lastPathComponent
        }
        return "GitHub Actions"
    }

    var run: Run {
        let jobs = jobs.map(\.job)
        let status = RunStatus.summing(jobs)
        return Run(
            id: id,
            name: name,
            status: status,
            conclusion: Conclusion.summing(jobs),
            webURL: Run.gitHubPage(
                jobPages: self.jobs.compactMap(\.githubUrl),
                repository: repository,
                runID: id
            ),
            createdAt: jobs.compactMap(\.createdAt).min() ?? .distantPast,
            startedAt: jobs.compactMap(\.startedAt).min(),
            completedAt: status == .completed ? jobs.compactMap(\.completedAt).max() : nil
        )
    }

    func activeRun(in repository: Repository, includeJobs: Bool) -> ActiveRun {
        ActiveRun(repository: repository, run: run, jobs: includeJobs ? jobs.map(\.job) : nil)
    }
}

/// `ListGithubActionsConnections`, and `ListGithubActionsRepositories` for one connection.
struct DepotPageRequest: ConnectPagedRequest {
    var connectionId: String?
    var pageSize: Int
    var pageToken: String?

    func after(_ token: String) -> DepotPageRequest {
        var next = self
        next.pageToken = token
        return next
    }
}

struct DepotGitHubConnectionsPage: ConnectPage {
    /// The most connections a page holds.
    static let pageSize = 100

    let connections: [DepotGitHubConnection]?
    let nextPageToken: String?

    var items: [DepotGitHubConnection] {
        connections ?? []
    }

    var nextPage: String? {
        nextPageToken
    }
}

/// The Depot GitHub App installed on a GitHub account.
struct DepotGitHubConnection: Decodable, Sendable {
    let connectionId: String
    /// The GitHub organization or user.
    let account: String?
    /// `GITHUB_ACTIONS_CONNECTION_STATUS_ACTIVE`, `…_PENDING` or `…_SUSPENDED`.
    let status: String?

    /// Not waiting to be installed, nor suspended.
    var isActive: Bool {
        status != "GITHUB_ACTIONS_CONNECTION_STATUS_PENDING"
            && status != "GITHUB_ACTIONS_CONNECTION_STATUS_SUSPENDED"
    }
}

struct DepotGitHubRepositoriesPage: ConnectPage {
    /// The most repositories a page holds.
    static let pageSize = 250

    let repositories: [DepotGitHubRepository]?
    let nextPageToken: String?

    var items: [DepotGitHubRepository] {
        repositories ?? []
    }

    var nextPage: String? {
        nextPageToken
    }
}

/// A repository the Depot GitHub App can see.
struct DepotGitHubRepository: Decodable, Sendable {
    /// `owner/name`
    let repository: String
    let `private`: Bool?

    var domain: Repository {
        Repository(gitHubFullName: repository, isPrivate: `private` ?? false)
    }
}
