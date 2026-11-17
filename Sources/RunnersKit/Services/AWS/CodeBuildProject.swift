import Foundation

/// A CodeBuild project as `BatchGetProjects` reports it.
struct CodeBuildProject: Codable, Sendable, Hashable {
    struct Webhook: Codable, Sendable, Hashable {
        let filterGroups: [[Filter]]?
    }

    struct Filter: Codable, Sendable, Hashable {
        let type: String
        let pattern: String
    }

    let name: String
    let arn: String?
    /// How long a build may run, 60 by default.
    let timeoutInMinutes: Int?
    /// How long a build may wait in the queue, 480 by default.
    let queuedTimeoutInMinutes: Int?
    let webhook: Webhook?

    /// A runner project: its webhook starts a build for each queued GitHub Actions job.
    var isRunnerProject: Bool {
        (webhook?.filterGroups ?? []).joined().contains {
            $0.type == "EVENT" && $0.pattern.contains("WORKFLOW_JOB_QUEUED")
        }
    }

    /// The longest a build can go on: queued, then running, with a quarter hour to finish up.
    /// A build that started longer ago than this has finished.
    var lifetime: TimeInterval {
        TimeInterval((queuedTimeoutInMinutes ?? 480) + (timeoutInMinutes ?? 60) + 15) * 60
    }

    func repository(in region: AWSRegion) -> Repository {
        Repository(
            id: name,
            name: name,
            fullName: name,
            webURL: region.projectPage(name, account: AWSARN.account(arn))
        )
    }

    /// A project name: 2 to 150 letters, digits, hyphens and underscores, starting with a
    /// letter or digit.
    static func isName(_ name: String) -> Bool {
        (2...150).contains(name.count)
            && name.first.map { $0.isASCII && ($0.isLetter || $0.isNumber) } == true
            && name.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
            }
    }
}
