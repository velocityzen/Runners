import FP
import Foundation

/// A CodeBuild build as `BatchGetBuilds` reports it. In a runner project, each build runs one
/// GitHub Actions job.
struct CodeBuildBuild: Codable, Sendable, Hashable {
    struct Phase: Codable, Sendable, Hashable {
        let phaseType: String
        let phaseStatus: String?
        let startTime: Date?
        let endTime: Date?
    }

    struct Source: Codable, Sendable, Hashable {
        let type: String?
        let location: String?
    }

    struct Environment: Codable, Sendable, Hashable {
        struct Fleet: Codable, Sendable, Hashable {
            let fleetArn: String?
        }

        let type: String?
        let image: String?
        let computeType: String?
        let fleet: Fleet?
    }

    /// `<project>:<uuid>`
    let id: String
    let arn: String?
    let buildNumber: Int?
    let projectName: String?
    /// `IN_PROGRESS`, `SUCCEEDED`, `FAILED`, `FAULT`, `TIMED_OUT` or `STOPPED`.
    let buildStatus: String?
    let buildComplete: Bool?
    let currentPhase: String?
    /// When the build was submitted.
    let startTime: Date?
    let endTime: Date?
    /// The phases it has reached, in order.
    let phases: [Phase]?
    let sourceVersion: String?
    /// The commit it builds.
    let resolvedSourceVersion: String?
    /// Who or what started it: a user, `codepipeline/<name>`, or `GitHub-Hookshot/…` for a
    /// webhook.
    let initiator: String?
    let source: Source?
    let environment: Environment?

    var isComplete: Bool {
        buildComplete ?? (buildStatus.map { $0 != "IN_PROGRESS" } ?? false)
    }

    var status: RunStatus {
        isComplete ? .completed : RunStatus(codeBuildPhase: currentPhase)
    }

    var conclusion: Conclusion? {
        isComplete ? Conclusion(codeBuild: buildStatus) : nil
    }

    var project: String {
        projectName ?? String(id.split(separator: ":").first ?? Substring(id))
    }

    /// When a runner got going: the start of the first phase past provisioning.
    var runningSince: Date? {
        phases?.first { !RunStatus.codeBuildWaitingPhases.contains($0.phaseType) }?.startTime
    }

    /// The GitHub repository it builds, `octo/app`, when its source is a repository URL.
    var repositoryName: String? {
        guard let location = source?.location, let url = URL(string: location), url.host() != nil
        else { return nil }
        let parts = url.path().split(separator: "/").suffix(2)
        guard parts.count == 2, let name = parts.last else { return nil }
        let bare = name.hasSuffix(".git") ? name.dropLast(4) : name
        return "\(parts.first ?? "")/\(bare)"
    }

    /// The branch, when the source version names one rather than a commit.
    var branch: String? {
        guard let version = sourceVersion, !version.isEmpty, !Self.isCommit(version) else {
            return nil
        }
        return version.hasPrefix("refs/heads/") ? String(version.dropFirst(11)) : version
    }

    /// `webhook` for a GitHub webhook, `codepipeline` for a pipeline; nil when a user started it.
    var trigger: String? {
        guard let initiator else { return nil }
        if initiator.hasPrefix("GitHub-Hookshot") { return "webhook" }
        if initiator.hasPrefix("codepipeline/") { return "codepipeline" }
        return nil
    }

    /// The user who started it.
    var actor: String? {
        trigger == nil ? initiator : nil
    }

    /// The image without CodeBuild's own prefix: `amazonlinux-x86_64-standard:5.0`.
    var image: String? {
        environment?.image.map { image in
            image.hasPrefix("aws/codebuild/") ? String(image.dropFirst(14)) : image
        }
    }

    // MARK: - Domain

    func run(in region: AWSRegion) -> Run {
        Run(
            id: id,
            name: project,
            title: repositoryName,
            number: buildNumber,
            trigger: trigger,
            status: status,
            conclusion: conclusion,
            branch: branch,
            commit: resolvedSourceVersion,
            webURL: page(in: region),
            createdAt: startTime ?? Date(timeIntervalSince1970: 0),
            startedAt: runningSince,
            completedAt: isComplete ? endTime : nil,
            actor: actor
        )
    }

    /// The build as its one job: named by its compute, queued for its environment and fleet,
    /// run by its image, on its current phase.
    func job(in region: AWSRegion) -> Job {
        Job(
            id: id,
            name: environment?.computeType ?? "build",
            status: status,
            conclusion: conclusion,
            createdAt: startTime,
            startedAt: runningSince,
            completedAt: isComplete ? endTime : nil,
            labels: [environment?.type, AWSARN.resourceName(environment?.fleet?.fleetArn)]
                .compact(),
            runner: image,
            currentStep: currentPhase.map(RunStatus.codeBuildPhrase),
            webURL: page(in: region)
        )
    }

    func activeRun(in repository: Repository, region: AWSRegion, includeJobs: Bool) -> ActiveRun {
        ActiveRun(
            repository: repository,
            run: run(in: region),
            jobs: includeJobs ? [job(in: region)] : nil
        )
    }

    func page(in region: AWSRegion) -> URL {
        region.buildPage(id, project: project, account: AWSARN.account(arn))
    }

    static func isCommit(_ version: String) -> Bool {
        version.count == 40 && version.allSatisfy(\.isHexDigit)
    }
}
