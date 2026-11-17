import FP
import Foundation

/// Depot's API speaks Connect: each method is a `POST` of JSON to
/// `/<package>.<Service>/<Method>`, answered in JSON. These are the Depot CI methods the
/// service calls.
struct DepotAPI: Sendable {
    static let ciService = "depot.ci.v1.CIService"
    /// The most runs `ListRuns` gives at a time.
    static let pageSize = 100

    let client: APIClient

    static func headers(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Connect-Protocol-Version": "1",
            "User-Agent": "Runners",
        ]
    }

    /// Connect names the error in the body, `{"code": "not_found", "message": …}`, and maps it
    /// onto an HTTP status, which the shared rules read for the rest.
    @Sendable
    static func classify(_ response: HTTPResponse, _ url: URL) -> RunnersError {
        let body = JSONCoding.decode(ConnectError.self, from: response.body).getOrElse { _ in
            ConnectError()
        }
        let message = body.message ?? body.code ?? "HTTP \(response.status)"
        switch body.code ?? "" {
            case "unauthenticated":
                return .unauthorized(
                    "\(message); DEPOT_TOKEN takes an organization API token, from Settings → "
                        + "API Tokens in the Depot dashboard"
                )
            case "permission_denied": return .forbidden(message)
            case "not_found": return .notFound(message)
            default: return RunnersError(response: response, url: url)
        }
    }

    func call<T: Decodable>(
        _ method: String,
        _ request: some Encodable,
        as type: T.Type = T.self
    ) async -> Result<T, RunnersError> {
        await client.post([Self.ciService, method], body: request, as: type)
    }

    /// The organization's runs with these statuses, newest first, or only one repository's.
    /// Pages until a page has no token for the next.
    func runs(statuses: [String], repo: String? = nil) async -> Result<[DepotRun], RunnersError> {
        await page(DepotListRuns(status: statuses, pageSize: Self.pageSize, repo: repo), [])
    }

    func page(
        _ request: DepotListRuns,
        _ found: [DepotRun]
    ) async -> Result<[DepotRun], RunnersError> {
        await call("ListRuns", request, as: DepotRunsPage.self)
            .flatMapAsync { page in
                let runs = found + (page.runs ?? [])
                guard let token = page.nextPageToken, !token.isEmpty, !(page.runs ?? []).isEmpty
                else { return .success(runs) }
                return await self.page(request.after(token), runs)
            }
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

/// The error a Connect call answers with.
struct ConnectError: Decodable {
    var code: String?
    var message: String?
}
