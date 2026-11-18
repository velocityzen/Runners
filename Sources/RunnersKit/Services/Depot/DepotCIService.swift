import FPRetry
import Foundation

/// Depot CI: the workflows of an organization's runs, from Depot's Connect API.
///
/// Each workflow of a Depot run shows as a run of its own, as a GitHub workflow run does: a
/// push that starts a build and a lint workflow is two runs, each with its jobs and its page
/// on depot.dev.
public struct DepotCIService: CIService {
    let api: DepotAPI

    public var provider: any Provider { DepotCIProvider() }

    /// - Parameters:
    ///   - token: a Depot organization API token.
    ///   - baseURL: the API, `https://api.depot.dev` unless `DEPOT_API_URL` says otherwise.
    public init(
        token: String,
        baseURL: URL = DepotCIService.defaultBaseURL,
        transport: any HTTPTransport = ConditionalTransport(URLSessionTransport()),
        retryPolicy: RetryPolicy = APIClient.defaultRetryPolicy
    ) {
        api = DepotAPI(
            connect: ConnectClient(
                baseURL: baseURL,
                token: token,
                tokenHelp: DepotAPI.tokenHelp,
                transport: transport,
                retryPolicy: retryPolicy
            )
        )
    }

    /// `https://api.depot.dev`
    public static var defaultBaseURL: URL {
        URL(string: "https://api.depot.dev") ?? URL(filePath: "/")
    }

    /// Depot reports no quota.
    public func rateLimit() async -> RateLimit? {
        nil
    }
}
