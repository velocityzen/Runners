import FP
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Sends requests with `URLSession`, bypassing its cache so every refresh sees fresh data.
public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(session: URLSession = URLSessionTransport.uncachedSession()) {
        self.session = session
    }

    public static func uncachedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async -> Result<HTTPResponse, GitHubError> {
        await load(request.urlRequest)
            .flatMap(HTTPResponse.from)
    }

    private func load(_ request: URLRequest) async -> Result<(Data, URLResponse), GitHubError> {
        await Result.fromAsync { try await session.data(for: request) }
            .mapError { .transport($0.localizedDescription) }
    }
}
