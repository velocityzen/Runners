import FP
import Foundation

/// The CodeBuild operations the service calls, answering in CodeBuild's own shapes.
struct CodeBuildAPI: Sendable {
    let client: AWSJSONClient
    let region: AWSRegion

    /// The most names or IDs one `BatchGet…` call takes.
    static let batchLimit = 100

    /// Every project's name, page by page.
    func projectNames(after token: String? = nil) async -> Result<[String], RunnersError> {
        await client.call(
            "ListProjects",
            ListProjects(sortBy: "NAME", nextToken: token),
            as: ProjectNames.self
        )
        .flatMapAsync { page in
            guard let next = page.nextToken else { return .success(page.projects ?? []) }
            return await projectNames(after: next).map { (page.projects ?? []) + $0 }
        }
    }

    /// The named projects, a hundred at a time, and the names that name none.
    func projects(
        _ names: [String],
        concurrency: Int
    ) async -> Result<(found: [CodeBuildProject], missing: [String]), RunnersError> {
        let client = client
        return await names.chunks(of: Self.batchLimit)
            .traverseAsync(concurrency: concurrency) { batch in
                await client.call("BatchGetProjects", ["names": batch], as: Projects.self)
            }
            .map { pages in
                (
                    found: pages.flatMap { $0.projects ?? [] },
                    missing: pages.flatMap { $0.projectsNotFound ?? [] }
                )
            }
    }

    /// One page of a project's build IDs, newest first.
    func buildIDs(
        of project: String,
        after token: String?
    ) async -> Result<BuildIDs, RunnersError> {
        await client.call(
            "ListBuildsForProject",
            ListBuildsForProject(projectName: project, sortOrder: "DESCENDING", nextToken: token),
            as: BuildIDs.self
        )
    }

    /// The builds with these IDs, which can be no more than a hundred.
    func builds(_ ids: [String]) async -> Result<[CodeBuildBuild], RunnersError> {
        guard !ids.isEmpty else { return .success([]) }
        return await client.call("BatchGetBuilds", ["ids": ids], as: Builds.self)
            .map { $0.builds ?? [] }
    }

    // MARK: - Shapes

    struct ListProjects: Encodable {
        let sortBy: String
        let nextToken: String?
    }

    struct ProjectNames: Codable {
        let projects: [String]?
        let nextToken: String?
    }

    struct Projects: Codable {
        let projects: [CodeBuildProject]?
        let projectsNotFound: [String]?
    }

    struct ListBuildsForProject: Encodable {
        let projectName: String
        let sortOrder: String
        let nextToken: String?
    }

    struct BuildIDs: Codable {
        let ids: [String]?
        let nextToken: String?
    }

    struct Builds: Codable {
        let builds: [CodeBuildBuild]?
        let buildsNotFound: [String]?
    }
}

extension Array {
    /// The elements in runs of `size`, the last one shorter.
    func chunks(of size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
