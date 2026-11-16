import FP
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Sends requests with `URLSession`, bypassing its cache so every refresh sees fresh data.
public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(session: URLSession = URLSessionTransport.shared) {
        self.session = session
    }

    /// The uncached session every transport shares, kept for the life of the process: on Linux,
    /// FoundationNetworking aborts when a session that sent requests is deallocated
    /// (`_MultiHandle deallocated with non-zero retain count`).
    public static let shared = uncachedSession()

    public static func uncachedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async -> Result<HTTPResponse, RunnersError> {
        await load(request.urlRequest)
            .flatMap(HTTPResponse.from)
    }

    private func load(_ request: URLRequest) async -> Result<(Data, URLResponse), RunnersError> {
        await Result.fromAsync { try await session.data(for: request) }
            .mapError { .transport($0.localizedDescription) }
    }
}
