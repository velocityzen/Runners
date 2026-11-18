import FP
import Foundation

/// WarpBuild's REST API: runner sets and the instances started for them.
struct WarpBuildAPI: Sendable {
    /// The most instances to ask for at a time.
    static let pageSize = 100
    /// Added to the message when WarpBuild rejects the key.
    static let keyHelp =
        "WARPBUILD_API_KEY takes an API key with the CI scope, from API Keys in the WarpBuild "
        + "dashboard"

    let client: APIClient

    static func headers(key: String) -> [String: String] {
        [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json",
            "User-Agent": "Runners",
        ]
    }

    /// WarpBuild says why in the body's `description`, which the shared rules don't read.
    @Sendable
    static func classify(_ response: HTTPResponse, _ url: URL) -> RunnersError {
        let text = JSONCoding.decode(WarpBuildError.self, from: response.body)
            .map(\.text)
            .getOrElse(nil)
        switch (response.status, text) {
            case (401, let text):
                return .unauthorized("\(text ?? "HTTP 401"); \(keyHelp)")
            case (403, let text?): return .forbidden(text)
            case (404, let text?): return .notFound(text)
            default: return RunnersError(response: response, url: url)
        }
    }

    /// The organization's runner sets.
    func runnerSets() async -> Result<[WarpBuildRunnerSet], RunnersError> {
        await client.value(["runners"])
    }

    /// The instances with these statuses, WarpBuild's own cloud runners included, every page;
    /// with none, the latest page of every status.
    func instances(statuses: [String]) async -> Result<[WarpBuildInstance], RunnersError> {
        await page(1, statuses: statuses, all: !statuses.isEmpty, [])
    }

    func page(
        _ number: Int,
        statuses: [String],
        all: Bool,
        _ found: [WarpBuildInstance]
    ) async -> Result<[WarpBuildInstance], RunnersError> {
        let query =
            statuses.map { URLQueryItem(name: "status", value: $0) } + [
                URLQueryItem(name: "include_cloud_runners", value: "true"),
                URLQueryItem(name: "per_page", value: String(Self.pageSize)),
                URLQueryItem(name: "page", value: String(number)),
            ]
        return await client.value(["runner_instance"], query, as: WarpBuildInstancesPage.self)
            .flatMapAsync { page in
                let instances = found + (page.runnerInstances ?? [])
                guard all, let next = page.next else { return .success(instances) }
                return await self.page(next, statuses: statuses, all: all, instances)
            }
    }

    /// One instance as it is now.
    func instance(_ id: String) async -> Result<WarpBuildInstance, RunnersError> {
        await client.value(["runner_instance", id])
    }
}
