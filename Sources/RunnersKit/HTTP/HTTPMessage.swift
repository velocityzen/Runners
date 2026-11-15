import Foundation

/// A GET request: the read APIs this library uses need nothing more.
public struct HTTPRequest: Sendable, Hashable {
    public var url: URL
    public var headers: [String: String]

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}

/// A response with header names lowercased.
public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    public var isSuccess: Bool {
        (200..<300).contains(status)
    }
}

/// The seam between the API clients and the network. Tests replace it with canned responses.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async -> Result<HTTPResponse, RunnersError>
}
