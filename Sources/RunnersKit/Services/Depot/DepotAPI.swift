import FP
import Foundation

/// Depot's API, served over Connect. These are the Depot CI methods the service calls; the
/// GitHub Actions ones are in `DepotAPI+GitHubActions.swift`.
struct DepotAPI: Sendable {
    static let ciService = "depot.ci.v1.CIService"
    /// The most runs `ListRuns` gives at a time.
    static let pageSize = 100
    /// Added to the message when Depot rejects the token.
    static let tokenHelp =
        "DEPOT_TOKEN takes an organization API token, from Settings → API Tokens in the Depot "
        + "dashboard"

    let connect: ConnectClient

    func call<T: Decodable>(
        _ method: String,
        _ request: some Encodable,
        as type: T.Type = T.self
    ) async -> Result<T, RunnersError> {
        await connect.call(Self.ciService, method, request, as: type)
    }

    /// The organization's runs with these statuses, newest first, or only one repository's,
    /// every page.
    func runs(statuses: [String], repo: String? = nil) async -> Result<[DepotRun], RunnersError> {
        await connect.all(
            Self.ciService,
            "ListRuns",
            DepotListRuns(status: statuses, pageSize: Self.pageSize, repo: repo),
            as: DepotRunsPage.self
        )
    }

    /// The organization's latest runs, finished or not: one page.
    func recentRuns() async -> Result<[DepotRun], RunnersError> {
        await call(
            "ListRuns",
            DepotListRuns(status: DepotRun.statuses, pageSize: Self.pageSize),
            as: DepotRunsPage.self
        )
        .map { $0.runs ?? [] }
    }

    /// A run's workflows and their jobs, with statuses only.
    func runStatus(_ runID: String) async -> Result<DepotRunStatus, RunnersError> {
        await call("GetRunStatus", ["runId": runID])
    }

    /// One job: its times, its conclusion and the machine it asks for.
    func job(_ jobID: String) async -> Result<DepotJob, RunnersError> {
        await call("GetJob", ["jobId": jobID])
    }

    /// One workflow, with its run's context and its jobs' times.
    func workflow(_ workflowID: String) async -> Result<DepotWorkflow, RunnersError> {
        await call("GetWorkflow", ["workflowId": workflowID])
    }
}
