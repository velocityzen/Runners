import FP

extension DepotAPI {
    static let gitHubActionsService = "depot.core.v1.GithubActionsService"

    /// The organization's GitHub Actions jobs with these statuses, newest first, every page;
    /// only these repositories' when it names any.
    func gitHubJobs(
        statuses: [String],
        repositories: [String]? = nil
    ) async -> Result<[DepotGitHubJob], RunnersError> {
        await connect.all(
            Self.gitHubActionsService,
            "ListGithubActionsJobs",
            DepotListGitHubJobs(repositories: repositories, statuses: statuses),
            as: DepotGitHubJobsPage.self
        )
    }

    /// Every job of one workflow run that ran on Depot, finished or not. The listing's query
    /// matches run IDs exactly, and job names too, so the jobs are kept to the run.
    func gitHubJobs(
        ofRun runID: String,
        in repository: String
    ) async -> Result<[DepotGitHubJob], RunnersError> {
        await connect.all(
            Self.gitHubActionsService,
            "ListGithubActionsJobs",
            DepotListGitHubJobs(repositories: [repository], query: runID),
            as: DepotGitHubJobsPage.self
        )
        .map { jobs in jobs.filter { $0.runId == runID } }
    }

    /// The GitHub accounts the Depot GitHub App is installed on.
    func gitHubConnections() async -> Result<[DepotGitHubConnection], RunnersError> {
        await connect.all(
            Self.gitHubActionsService,
            "ListGithubActionsConnections",
            DepotPageRequest(pageSize: DepotGitHubConnectionsPage.pageSize),
            as: DepotGitHubConnectionsPage.self
        )
    }

    /// The repositories one installation of the app can see.
    func gitHubRepositories(
        of connection: DepotGitHubConnection
    ) async -> Result<[DepotGitHubRepository], RunnersError> {
        await connect.all(
            Self.gitHubActionsService,
            "ListGithubActionsRepositories",
            DepotPageRequest(
                connectionId: connection.connectionId,
                pageSize: DepotGitHubRepositoriesPage.pageSize
            ),
            as: DepotGitHubRepositoriesPage.self
        )
    }
}
