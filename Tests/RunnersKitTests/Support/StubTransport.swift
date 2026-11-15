import Foundation
import Synchronization

@testable import RunnersKit

/// Answers requests from a function and records them.
final class StubTransport: HTTPTransport {
    /// Gets the request and how many times its URL was asked for before.
    typealias Responder = @Sendable (HTTPRequest, Int) -> HTTPResponse

    private let responder: Responder
    private let log = Mutex<[HTTPRequest]>([])

    init(_ responder: @escaping Responder) {
        self.responder = responder
    }

    var requests: [HTTPRequest] {
        log.withLock { $0 }
    }

    var paths: [String] {
        requests.map { $0.url.path() }
    }

    func send(_ request: HTTPRequest) async -> Result<HTTPResponse, GitHubError> {
        let attempt = log.withLock { log in
            defer { log.append(request) }
            return log.count { $0.url == request.url }
        }
        return .success(responder(request, attempt))
    }
}

extension HTTPRequest {
    func query(_ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}

extension HTTPResponse {
    static func json(_ value: some Encodable, headers: [String: String] = [:]) -> HTTPResponse {
        let body = (try? GitHubJSON.encoder.encode(value)) ?? Data()
        return HTTPResponse(status: 200, headers: headers, body: body)
    }

    static func raw(_ status: Int, _ body: String = "", headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: status, headers: headers, body: Data(body.utf8))
    }

    static let notFound = raw(404, #"{"message":"Not Found"}"#)
}
