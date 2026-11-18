import FP
import Foundation

// `namespace.cloud.github.v1beta`'s messages, from `jobs.proto` and `profiles.proto` on
// buf.build/namespace/cloud. A job has no status: its times say where it is. 64-bit integers
// come as strings, bytes in base64, times in RFC 3339; a field at its default is left out.

/// `ListJobs`. Every filter may be left out.
struct NamespaceListJobs: ConnectPagedRequest {
    /// The most jobs to ask for at a time.
    static let pageSize: Int64 = 100

    /// From the previous page, to read on with the same filters.
    var paginationCursor: String?
    var maxEntries = ProtoInt64(Self.pageSize)
    /// On when the job was created.
    var timeRange: NamespaceTimeRange?
    var repository: NamespaceStringMatcher?
    /// Only jobs that have not started.
    var hasNotStarted: Bool?
    /// Only jobs that have not finished: those not started too.
    var hasNotFinished: Bool?

    func after(_ token: String) -> NamespaceListJobs {
        var next = self
        next.paginationCursor = token
        return next
    }
}

/// `namespace.stdlib.TimestampRange`
struct NamespaceTimeRange: Encodable, Sendable {
    /// RFC 3339
    var after: String?
}

/// `namespace.stdlib.StringMatcher`: any of these values.
struct NamespaceStringMatcher: Encodable, Sendable {
    var values: [String]
    var op = "IS_ANY_OF"
}

struct NamespaceJobsPage: ConnectPage {
    let jobs: [NamespaceJob]?
    /// Base64; absent on the last page.
    let paginationCursor: String?

    var items: [NamespaceJob] {
        jobs ?? []
    }

    var nextPage: String? {
        paginationCursor
    }
}

/// `DescribeJob`
struct NamespaceJobDescription: Decodable, Sendable {
    let job: NamespaceJob?
}

/// A GitHub Actions job on a Namespace runner.
struct NamespaceJob: Decodable, Sendable, Hashable {
    struct Runner: Decodable, Sendable, Hashable {
        let runnerName: String?
        /// The compute instance it runs on.
        let instanceId: String?
    }

    struct Profile: Decodable, Sendable, Hashable {
        /// What `runs-on: namespace-profile-<tag>` names.
        let tag: String?
    }

    /// GitHub's job ID.
    let jobId: ProtoInt64
    /// `owner/name`
    let repository: String?
    /// GitHub's workflow run ID.
    let runId: ProtoInt64?
    let workflowName: String?
    let jobName: String?
    /// GitHub's: `success`, `failure`, `cancelled`, …; unset until it completes.
    let conclusion: String?
    let jobUrl: String?
    /// Who started the workflow.
    let senderLogin: String?
    let ref: String?
    /// When GitHub created it.
    let createdAt: String?
    let queuedAt: String?
    let startedAt: String?
    let completedAt: String?
    /// Set once a runner has it.
    let runner: Runner?
    let profile: Profile?

    var id: String {
        String(jobId.value)
    }

    /// Completed once it has an end, running once it has a start, queued before.
    var status: RunStatus {
        if ProtoTime.date(completedAt) != nil { return .completed }
        return ProtoTime.date(startedAt) != nil ? .running : .queued
    }

    var created: Date? {
        ProtoTime.date(createdAt)
    }

    var profileTag: String? {
        profile?.tag.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The runner, its instance, the machine its profile gives, and how long it waited:
    /// `nsc-runner-1, instance i-1, 4 CPUs, 8 GB, linux arm64, 3s in queue`.
    func runnerDescription(shape: NamespaceShape?) -> String? {
        let name = runner?.runnerName.flatMap { $0.isEmpty ? nil : $0 }
        let instance = runner?.instanceId.flatMap { id in
            id.isEmpty || name?.contains(id) == true ? nil : "instance \(id)"
        }
        let waited = ProtoTime.date(startedAt).flatMap { started in
            Elapsed.between(ProtoTime.date(queuedAt), started).map { "\($0) in queue" }
        }
        let parts = [name, instance, shape?.description, waited].compact()
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    func job(shape: NamespaceShape?) -> Job {
        let status = status
        return Job(
            id: id,
            name: jobName.flatMap { $0.isEmpty ? nil : $0 } ?? "job",
            status: status,
            conclusion: status == .completed
                ? conclusion.flatMap { $0.isEmpty ? nil : Conclusion(gitHub: $0) } : nil,
            createdAt: created,
            startedAt: ProtoTime.date(startedAt),
            completedAt: ProtoTime.date(completedAt),
            labels: profileTag.map { ["namespace-profile-\($0)"] } ?? [],
            runner: runnerDescription(shape: shape),
            webURL: jobUrl.flatMap(URL.init(string:))
        )
    }
}

/// A GitHub workflow run, as far as Namespace knows it: by the jobs of it on Namespace's
/// runners.
struct NamespaceRun: Sendable {
    let id: String
    let repository: String
    /// The newest attempt of each job, oldest first.
    let jobs: [NamespaceJob]

    init(id: String, repository: String, jobs: [NamespaceJob]) {
        self.id = id
        self.repository = repository
        self.jobs = jobs.newestAttempts(name: { $0.jobName ?? $0.id }, created: \.created)
    }

    /// The runs these jobs belong to, in the order their first jobs come.
    static func runs(of jobs: [NamespaceJob]) -> [NamespaceRun] {
        jobs.grouped { job -> String? in
            guard let runID = job.runId, let repository = job.repository, !repository.isEmpty
            else { return nil }
            return "\(repository.lowercased())/\(runID.value)"
        }
        .compactMap { jobs in
            guard let runID = jobs.first?.runId, let repository = jobs.first?.repository else {
                return nil
            }
            return NamespaceRun(id: String(runID.value), repository: repository, jobs: jobs)
        }
    }

    /// `main` for `refs/heads/main`; any other ref as it is.
    var branch: String? {
        guard let ref = jobs.first?.ref, !ref.isEmpty else { return nil }
        return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
    }

    func run(shapes: [String: NamespaceShape]) -> Run {
        let domain = self.jobs(shapes: shapes)
        let status = RunStatus.summing(domain)
        let first = jobs.first
        return Run(
            id: id,
            name: first?.workflowName.flatMap { $0.isEmpty ? nil : $0 } ?? "GitHub Actions",
            status: status,
            conclusion: Conclusion.summing(domain),
            branch: branch,
            webURL: Run.gitHubPage(
                jobPages: jobs.compactMap(\.jobUrl),
                repository: repository,
                runID: id
            ),
            createdAt: domain.compactMap(\.createdAt).min() ?? .distantPast,
            startedAt: domain.compactMap(\.startedAt).min(),
            completedAt: status == .completed ? domain.compactMap(\.completedAt).max() : nil,
            actor: first?.senderLogin.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    func jobs(shapes: [String: NamespaceShape]) -> [Job] {
        jobs.map { $0.job(shape: $0.profileTag.flatMap { shapes[$0] }) }
    }

    func activeRun(
        in repository: Repository,
        shapes: [String: NamespaceShape],
        includeJobs: Bool
    ) -> ActiveRun {
        ActiveRun(
            repository: repository,
            run: run(shapes: shapes),
            jobs: includeJobs ? jobs(shapes: shapes) : nil
        )
    }
}

/// `ListProfiles`
struct NamespaceProfiles: Decodable, Sendable {
    struct Profile: Decodable, Sendable {
        struct Spec: Decodable, Sendable {
            let tag: String?
            let instanceShape: NamespaceShape?
        }

        let profileId: String?
        let spec: Spec?
    }

    let profiles: [Profile]?

    /// Each profile's machine, by its tag.
    var shapes: [String: NamespaceShape] {
        Dictionary(
            (profiles ?? []).compactMap { profile in
                guard let tag = profile.spec?.tag, let shape = profile.spec?.instanceShape else {
                    return nil
                }
                return (tag, shape)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

/// `namespace.cloud.compute.v1beta.InstanceShape`: the machine a profile's runners get.
struct NamespaceShape: Decodable, Sendable, Hashable {
    let virtualCpu: Int?
    let memoryMegabytes: Int?
    /// `amd64` or `arm64`
    let machineArch: String?
    /// `linux` or `macos`
    let os: String?

    /// `4 CPUs, 8 GB, linux arm64`
    var description: String? {
        let platform = [os, machineArch].compact().filter { !$0.isEmpty }.joined(separator: " ")
        let parts = [
            MachineSize.describe(
                cpus: virtualCpu,
                memoryGB: memoryMegabytes.map { Double($0) / 1024 }
            ),
            platform.isEmpty ? nil : platform,
        ]
        .compact()
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
