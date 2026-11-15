import Foundation

@testable import RunnersKit

/// GitLab's wire shapes.
enum GitLabFixtures {
    static let me = GitLabUser(id: 1, username: "octo")
    static let group = GitLabGroup(id: 50, fullPath: "acme")

    static func project(
        _ path: String,
        id: Int,
        archived: Bool = false,
        builds: String = "enabled",
        isFork: Bool = false
    ) -> GitLabProject {
        GitLabProject(
            id: id,
            name: String(path.split(separator: "/").last ?? ""),
            pathWithNamespace: path,
            webURL: Fixtures.url("https://gitlab.com/\(path)"),
            visibility: "private",
            archived: archived,
            buildsAccessLevel: builds,
            forkedFromProject: isFork ? .init(id: 999) : nil
        )
    }

    static func pipeline(_ id: Int, _ status: String, minutesAgo minutes: Double = 5)
        -> GitLabPipeline
    {
        GitLabPipeline(
            id: id,
            iid: id % 100,
            name: nil,
            status: status,
            source: "push",
            ref: "main",
            sha: "abc\(id)",
            webURL: Fixtures.url("https://gitlab.com/acme/api/-/pipelines/\(id)"),
            createdAt: Fixtures.minutesAgo(minutes),
            startedAt: Fixtures.minutesAgo(minutes),
            user: nil
        )
    }

    static func job(
        _ id: Int,
        _ name: String,
        _ status: String,
        pipeline: Int,
        pipelineStatus: String = "running",
        stage: String = "test",
        runner: String? = nil
    ) -> GitLabJob {
        GitLabJob(
            id: id,
            name: name,
            stage: stage,
            status: status,
            createdAt: Fixtures.minutesAgo(3),
            startedAt: status == "running" ? Fixtures.minutesAgo(2) : nil,
            finishedAt: nil,
            tagList: ["docker"],
            webURL: nil,
            runner: runner.map { .init(id: 7, description: $0) },
            pipeline: .init(id: pipeline, status: pipelineStatus),
            commit: .init(title: "Commit for \(pipeline)"),
            user: me
        )
    }
}

/// Just enough of the GitLab REST API to serve the service, from in-memory data.
struct FakeGitLab: Sendable {
    var user = GitLabFixtures.me
    var groups: [String: GitLabGroup] = [:]
    var users: [String: GitLabUser] = [:]
    /// Project lists by listing path, like `/groups/50/projects`.
    var listings: [String: [GitLabProject]] = [:]
    /// Every job of a project, by project ID; the fake filters them by `scope[]`.
    var projectJobs: [Int: [GitLabJob]] = [:]
    var pipelines: [Int: GitLabPipeline] = [:]
    var pipelineJobs: [Int: [GitLabJob]] = [:]

    var projects: [GitLabProject] {
        listings.values.flatMap { $0 }
    }

    func respond(_ request: HTTPRequest) -> HTTPResponse {
        let parts = request.url.path(percentEncoded: true)
            .split(separator: "/")
            .map { $0.removingPercentEncoding ?? String($0) }
            .dropFirst(2)  // api/v4
        let path = "/" + parts.joined(separator: "/")
        switch (parts.first, parts.count) {
            case ("user", 1): return .json(user)
            case ("users", 1):
                return .json(request.query("username").flatMap { users[$0] }.map { [$0] } ?? [])
            case ("groups", 2): return groups[parts.last ?? ""].map { .json($0) } ?? .notFound
            case (_, _) where parts.last == "projects":
                return listings[path].map { .json($0) } ?? .notFound
            case ("projects", 2): return project(parts.last ?? "").map { .json($0) } ?? .notFound
            case ("projects", 3...):
                return projectResource(
                    Int(parts.dropFirst().first ?? "") ?? 0,
                    Array(parts.dropFirst(2)),
                    request
                )
            default: return .notFound
        }
    }

    func project(_ idOrPath: String) -> GitLabProject? {
        projects.first { String($0.id) == idOrPath || $0.pathWithNamespace == idOrPath }
    }

    /// `/projects/{id}/…`
    func projectResource(_ projectID: Int, _ rest: [String], _ request: HTTPRequest) -> HTTPResponse
    {
        switch (rest.first, rest.count) {
            case ("jobs", 1):
                let scopes = request.queryValues("scope[]")
                return .json((projectJobs[projectID] ?? []).filter { scopes.contains($0.status) })
            case ("pipelines", 2):
                return Int(rest[1]).flatMap { pipelines[$0] }.map { .json($0) } ?? .notFound
            case ("pipelines", 3): return .json(Int(rest[1]).flatMap { pipelineJobs[$0] } ?? [])
            default: return .notFound
        }
    }

    func transport() -> StubTransport {
        StubTransport { request, _ in respond(request) }
    }
}
