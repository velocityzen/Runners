import Foundation

@testable import RunnersKit

/// CodeBuild's wire shapes.
enum AWSFixtures {
    static let account = "123456789012"
    static let endpoint = Fixtures.url("https://codebuild.us-east-1.amazonaws.com")
    static let credentials = AWSCredentials(accessKeyID: "AKIDEXAMPLE", secretAccessKey: "secret")

    // A valid name, so it never fails.
    static let region = AWSRegion("us-east-1")!

    /// A runner project, or a plain one.
    static func project(
        _ name: String,
        runner: Bool = true,
        timeout: Int? = nil,
        queuedTimeout: Int? = nil
    ) -> CodeBuildProject {
        CodeBuildProject(
            name: name,
            arn: "arn:aws:codebuild:us-east-1:\(account):project/\(name)",
            timeoutInMinutes: timeout,
            queuedTimeoutInMinutes: queuedTimeout,
            webhook: CodeBuildProject.Webhook(
                filterGroups: [
                    [
                        CodeBuildProject.Filter(
                            type: "EVENT",
                            pattern: runner ? "WORKFLOW_JOB_QUEUED" : "PUSH"
                        )
                    ]
                ]
            )
        )
    }

    /// A build submitted `minutesAgo`, in `phase`, its earlier phases done one minute each.
    static func build(
        _ project: String,
        _ number: Int,
        phase: String = "BUILD",
        status: String = "IN_PROGRESS",
        minutesAgo minutes: Double = 5,
        sourceVersion: String? = "refs/heads/main",
        initiator: String? = "GitHub-Hookshot/abc123"
    ) -> CodeBuildBuild {
        let order = [
            "SUBMITTED", "QUEUED", "PROVISIONING", "DOWNLOAD_SOURCE", "INSTALL", "PRE_BUILD",
            "BUILD", "POST_BUILD", "UPLOAD_ARTIFACTS", "FINALIZING", "COMPLETED",
        ]
        let reached = order.prefix { $0 != phase } + [phase]
        let phases = reached.enumerated().map { index, type in
            CodeBuildBuild.Phase(
                phaseType: type,
                phaseStatus: type == phase ? nil : "SUCCEEDED",
                startTime: Fixtures.minutesAgo(minutes - Double(index)),
                endTime: type == phase ? nil : Fixtures.minutesAgo(minutes - Double(index) - 1)
            )
        }
        let complete = status != "IN_PROGRESS"
        return CodeBuildBuild(
            id: "\(project):uuid-\(number)",
            arn: "arn:aws:codebuild:us-east-1:\(account):build/\(project):uuid-\(number)",
            buildNumber: number,
            projectName: project,
            buildStatus: status,
            buildComplete: complete,
            currentPhase: phase,
            startTime: Fixtures.minutesAgo(minutes),
            endTime: complete ? Fixtures.minutesAgo(1) : nil,
            phases: phases,
            sourceVersion: sourceVersion,
            resolvedSourceVersion: "0123456789abcdef0123456789abcdef01234567",
            initiator: initiator,
            source: CodeBuildBuild.Source(
                type: "GITHUB",
                location: "https://github.com/octo/app.git"
            ),
            environment: CodeBuildBuild.Environment(
                type: "LINUX_CONTAINER",
                image: "aws/codebuild/amazonlinux-x86_64-standard:5.0",
                computeType: "BUILD_GENERAL1_SMALL",
                fleet: nil
            )
        )
    }
}

/// A region's CodeBuild: projects, and each one's builds, newest first. It answers the four
/// operations the service calls, `pageSize` IDs a page.
struct FakeCodeBuild: Sendable {
    var projects: [CodeBuildProject] = []
    var builds: [String: [CodeBuildBuild]] = [:]
    var pageSize = 100

    struct Input: Decodable {
        let names: [String]?
        let ids: [String]?
        let projectName: String?
        let nextToken: String?
    }

    func transport() -> StubTransport {
        StubTransport { request, _ in respond(request) }
    }

    func respond(_ request: HTTPRequest) -> HTTPResponse {
        let operation = request.headers["X-Amz-Target"]?.split(separator: ".").last ?? ""
        let input =
            (try? JSONDecoder().decode(Input.self, from: request.body ?? Data()))
            ?? Input(names: nil, ids: nil, projectName: nil, nextToken: nil)
        switch operation {
            case "ListProjects":
                let page = self.page(projects.map(\.name).sorted(), after: input.nextToken)
                return Self.json(
                    CodeBuildAPI.ProjectNames(projects: page.items, nextToken: page.next)
                )
            case "BatchGetProjects":
                let names = input.names ?? []
                return Self.json(
                    CodeBuildAPI.Projects(
                        projects: projects.filter { names.contains($0.name) },
                        projectsNotFound: names.filter { name in
                            !projects.contains { $0.name == name }
                        }
                    )
                )
            case "ListBuildsForProject":
                let ids = (builds[input.projectName ?? ""] ?? []).map(\.id)
                let page = self.page(ids, after: input.nextToken)
                return Self.json(CodeBuildAPI.BuildIDs(ids: page.items, nextToken: page.next))
            case "BatchGetBuilds":
                let ids = input.ids ?? []
                let all = builds.values.joined()
                return Self.json(
                    CodeBuildAPI.Builds(
                        builds: ids.compactMap { id in all.first { $0.id == id } },
                        buildsNotFound: ids.filter { id in !all.contains { $0.id == id } }
                    )
                )
            default:
                return .raw(400, #"{"__type":"UnknownOperationException","message":"no"}"#)
        }
    }

    /// The items after the token's offset, and the next token when more are left.
    func page(_ items: [String], after token: String?) -> (items: [String], next: String?) {
        let start = token.flatMap(Int.init) ?? 0
        let end = min(start + pageSize, items.count)
        return (Array(items[start..<end]), end < items.count ? String(end) : nil)
    }

    static func json(_ value: some Encodable) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return HTTPResponse(status: 200, body: (try? encoder.encode(value)) ?? Data())
    }
}
