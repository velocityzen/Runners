import FP
import Foundation

// WarpBuild's REST API, `https://api.warpbuild.com/api/v1`, as its API reference gives it.
// Times are RFC 3339 strings, empty or absent until what they mark happens.

/// A runner set, from `GET /runners`: what a `runs-on` label maps to.
struct WarpBuildRunnerSet: Decodable, Sendable {
    let id: String
    let name: String?
    let active: Bool?
    let labels: [String]?

    var repository: Repository {
        WarpBuildGroup.repository(id: id, name: name.flatMap { $0.isEmpty ? nil : $0 } ?? id)
    }

    /// Whether `-r` names it: by ID, name or label.
    func isNamed(_ name: String) -> Bool {
        let name = name.lowercased()
        return id.lowercased() == name || self.name?.lowercased() == name
            || (labels ?? []).contains { $0.lowercased() == name }
    }
}

/// `GET /runner_instance`
struct WarpBuildInstancesPage: Decodable, Sendable {
    let page: Int?
    let nextPage: Int?
    let totalPages: Int?
    let runnerInstances: [WarpBuildInstance]?

    enum CodingKeys: String, CodingKey {
        case page
        case nextPage = "next_page"
        case totalPages = "total_pages"
        case runnerInstances = "runner_instances"
    }

    /// The page after this one, while there is one.
    var next: Int? {
        guard let nextPage, nextPage > (page ?? 0), !(runnerInstances ?? []).isEmpty else {
            return nil
        }
        return totalPages.map { nextPage <= $0 ? nextPage : nil } ?? nextPage
    }
}

/// A machine WarpBuild started for a runner set, and the GitHub job it last took.
struct WarpBuildInstance: Decodable, Sendable {
    struct JobMeta: Decodable, Sendable {
        let vcsOrg: String?
        let vcsRepo: String?
        let vcsWorkflowName: String?
        let vcsJobName: String?
        let vcsRef: String?
        let vcsHeadRef: String?
        let vcsStartTime: String?
        let vcsEndTime: String?

        enum CodingKeys: String, CodingKey {
            case vcsOrg = "vcs_org"
            case vcsRepo = "vcs_repo"
            case vcsWorkflowName = "vcs_workflow_name"
            case vcsJobName = "vcs_job_name"
            case vcsRef = "vcs_ref"
            case vcsHeadRef = "vcs_head_ref"
            case vcsStartTime = "vcs_start_time"
            case vcsEndTime = "vcs_end_time"
        }

        /// `octo/app`, from the organization and the repository, which may name both.
        var repository: String? {
            guard let repo = vcsRepo.flatMap({ $0.isEmpty ? nil : $0 }) else { return nil }
            if repo.contains("/") { return repo }
            return vcsOrg.flatMap { $0.isEmpty ? nil : "\($0)/\(repo)" } ?? repo
        }
    }

    struct Configuration: Decodable, Sendable {
        struct SKU: Decodable, Sendable {
            let displayName: String?
            let cores: Int?
            let memory: Int?
            /// `x64` or `arm64`
            let arch: String?

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case cores, memory, arch
            }

            /// Its display name, else its cores and memory: `4 CPUs, 16 GB, x64`.
            var description: String? {
                if let displayName, !displayName.isEmpty { return displayName }
                let parts = [
                    MachineSize.describe(cpus: cores, memoryGB: memory.map(Double.init)),
                    arch.flatMap { $0.isEmpty ? nil : $0 },
                ]
                .compact()
                return parts.isEmpty ? nil : parts.joined(separator: ", ")
            }
        }

        let sku: SKU?
        let stockRunnerSetId: String?

        enum CodingKeys: String, CodingKey {
            case sku
            case stockRunnerSetId = "stock_runner_set_id"
        }
    }

    let id: String
    /// `allocating`, `allocated`, `running`, `completed`, …
    let status: String?
    let labels: [String]?
    let runnerSetId: String?
    let lastJobProcessedId: String?
    let lastJobProcessedMeta: JobMeta?
    let configuration: Configuration?
    let createdAt: String?
    let allocationRequestedAt: String?
    let runningStartedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, labels, configuration
        case runnerSetId = "runner_set_id"
        case lastJobProcessedId = "last_job_processed_id"
        case lastJobProcessedMeta = "last_job_processed_meta"
        case createdAt = "created_at"
        case allocationRequestedAt = "allocation_requested_at"
        case runningStartedAt = "running_started_at"
    }

    var runStatus: RunStatus {
        RunStatus(warpBuild: status)
    }

    /// The runner set it belongs to: its own, else the stock one it was made from, else its
    /// first label.
    var groupID: String {
        [runnerSetId, configuration?.stockRunnerSetId, labels?.first]
            .compact()
            .first { !$0.isEmpty } ?? "warpbuild"
    }

    /// Its runner set, for an instance whose set `GET /runners` doesn't list, such as a stock
    /// runner's: named by its first label.
    var group: Repository {
        WarpBuildGroup.repository(id: groupID, name: labels?.first ?? groupID)
    }

    /// When it was asked for, which is when its job began to wait.
    var requested: Date? {
        ProtoTime.date(allocationRequestedAt) ?? ProtoTime.date(createdAt)
    }

    var started: Date? {
        ProtoTime.date(runningStartedAt)
    }

    /// When its job ended, once it has.
    var ended: Date? {
        runStatus == .completed ? ProtoTime.date(lastJobProcessedMeta?.vcsEndTime) : nil
    }

    /// The machine, and how long its job waited for it: `4 CPUs, 16 GB, x64, 12s in queue`.
    var runner: String? {
        let waited = started.flatMap { started in
            Elapsed.between(requested, started).map { "\($0) in queue" }
        }
        let parts = [configuration?.sku?.description, waited].compact()
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The job's repository on GitHub, where its runs are.
    var actionsPage: URL? {
        lastJobProcessedMeta?.repository.flatMap {
            URL(string: "https://github.com/\($0)/actions")
        }
    }

    /// `main` for `refs/heads/main`: the pull request's branch, else the ref.
    var branch: String? {
        let meta = lastJobProcessedMeta
        guard let ref = [meta?.vcsHeadRef, meta?.vcsRef].compact().first(where: { !$0.isEmpty })
        else { return nil }
        return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
    }

    /// The instance as a run of one job: named by its workflow, about its repository. How the
    /// job ended is not in the instance, so a finished run has no conclusion.
    var run: Run {
        Run(
            id: id,
            name: lastJobProcessedMeta?.vcsWorkflowName.flatMap { $0.isEmpty ? nil : $0 }
                ?? "WarpBuild",
            title: lastJobProcessedMeta?.repository,
            status: runStatus,
            branch: branch,
            webURL: actionsPage ?? WarpBuildGroup.dashboard,
            createdAt: requested ?? .distantPast,
            startedAt: started,
            completedAt: ended
        )
    }

    var job: Job {
        Job(
            id: lastJobProcessedId.flatMap { $0.isEmpty ? nil : $0 } ?? id,
            name: lastJobProcessedMeta?.vcsJobName.flatMap { $0.isEmpty ? nil : $0 } ?? "job",
            status: runStatus,
            createdAt: requested,
            startedAt: started,
            completedAt: ended,
            labels: labels ?? [],
            runner: runner,
            webURL: actionsPage
        )
    }

    func activeRun(in repository: Repository, includeJobs: Bool) -> ActiveRun {
        ActiveRun(repository: repository, run: run, jobs: includeJobs ? [job] : nil)
    }
}

/// Runner sets as the repositories runs group under.
enum WarpBuildGroup {
    /// `https://app.warpbuild.com`
    static var dashboard: URL {
        URL(string: "https://app.warpbuild.com") ?? URL(filePath: "/")
    }

    static func repository(id: String, name: String) -> Repository {
        Repository(id: id, name: name, fullName: name, webURL: dashboard)
    }
}

/// The error WarpBuild answers with: `{"code": "UNA", "message": "unauthorized access",
/// "description": "Failed to verify token: Invalid API key."}`.
struct WarpBuildError: Decodable {
    let message: String?
    let description: String?

    /// The description, which says why, else the message, without a closing period.
    var text: String? {
        [description, message].compact()
            .map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
            .first { !$0.isEmpty }
    }
}
