import FP
import Foundation

/// The GitLab REST endpoints the service reads, answering in GitLab's own shapes.
struct GitLabAPI: Sendable {
    let client: APIClient

    static func headers(token: String) -> [String: String] {
        [
            "Accept": "application/json",
            "Authorization": "Bearer \(token)",
            "User-Agent": "Runners",
        ]
    }

    /// The user the token belongs to.
    func currentUser() async -> Result<GitLabUser, RunnersError> {
        await client.value(["user"])
    }

    /// A group by ID or full path (`group/subgroup`).
    func group(_ path: String) async -> Result<GitLabGroup, RunnersError> {
        await client.value(["groups", path], [URLQueryItem(name: "with_projects", value: "false")])
    }

    /// Users by exact username: none or one.
    func users(named username: String) async -> Result<[GitLabUser], RunnersError> {
        await client.value(["users"], [URLQueryItem(name: "username", value: username)])
    }

    /// A project by ID or full path (`group/project`).
    func project(_ path: String) async -> Result<GitLabProject, RunnersError> {
        await client.value(["projects", path])
    }

    func projects(_ listing: GitLabListing) async -> Result<[GitLabProject], RunnersError> {
        await client.all(listing.path, listing.query, as: [GitLabProject].self)
    }

    /// The project's jobs that have not finished, newest first. Leaves out `manual` jobs:
    /// optional ones stay `manual` in finished pipelines forever.
    func unfinishedJobs(in projectID: String) async -> Result<[GitLabJob], RunnersError> {
        await client.all(
            ["projects", projectID, "jobs"],
            RunStatus.gitLabUnfinishedJobScopes.map { URLQueryItem(name: "scope[]", value: $0) } + [
                .perPage
            ],
            as: [GitLabJob].self
        )
    }

    func pipeline(
        _ pipelineID: Int,
        in projectID: String
    ) async -> Result<GitLabPipeline, RunnersError> {
        await client.value(["projects", projectID, "pipelines", String(pipelineID)])
    }

    func jobs(
        ofPipeline pipelineID: Int,
        in projectID: String
    ) async -> Result<[GitLabJob], RunnersError> {
        await client.all(
            ["projects", projectID, "pipelines", String(pipelineID), "jobs"],
            [.perPage],
            as: [GitLabJob].self
        )
    }

    /// Runners by the path that lists them: `runners`, `groups/:id/runners` or
    /// `projects/:id/runners`.
    func runners(_ path: [String]) async -> Result<[GitLabRunner], RunnersError> {
        await client.all(path, [.perPage], as: [GitLabRunner].self)
    }

    /// The jobs a runner is on, from the first page: a runner runs a few at a time at most.
    func runningJobs(of runnerID: Int) async -> Result<[GitLabRunnerJob], RunnersError> {
        await client.value(
            ["runners", String(runnerID), "jobs"],
            [URLQueryItem(name: "status", value: "running"), .perPage]
        )
    }
}
