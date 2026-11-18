import FP
import FPRetry
import Foundation

/// Calls an API served over Connect, as Depot's and Namespace's are: each method is a `POST`
/// of JSON to `/<package>.<Service>/<Method>`, answered in JSON.
///
/// Bodies follow proto3's JSON mapping: names in lowerCamelCase, 64-bit integers as strings,
/// timestamps in RFC 3339, enums by name, and a field left out when it holds its default, so
/// the models read most fields as optional.
struct ConnectClient: Sendable {
    let client: APIClient

    /// - Parameters:
    ///   - tokenHelp: Which token the service takes and where to get one, added to the message
    ///     of a call that rejects the token.
    ///   - rejectsToken: Whether an error rejects the token: by default, `unauthenticated`.
    init(
        baseURL: URL,
        token: String,
        tokenHelp: String,
        rejectsToken: @escaping @Sendable (ConnectError) -> Bool = { $0.code == "unauthenticated" },
        transport: any HTTPTransport,
        retryPolicy: RetryPolicy
    ) {
        client = APIClient(
            baseURL: baseURL,
            headers: Self.headers(token: token),
            transport: transport,
            retryPolicy: retryPolicy,
            classify: Self.classify(tokenHelp: tokenHelp, rejectsToken: rejectsToken)
        )
    }

    var baseURL: URL {
        client.baseURL
    }

    func call<T: Decodable>(
        _ service: String,
        _ method: String,
        _ request: some Encodable,
        as type: T.Type = T.self
    ) async -> Result<T, RunnersError> {
        await client.post([service, method], body: request, as: type)
    }

    /// Every item of a listing, page after page, until a page names no next one or comes back
    /// empty.
    func all<Request: ConnectPagedRequest, Page: ConnectPage>(
        _ service: String,
        _ method: String,
        _ request: Request,
        as page: Page.Type,
        found: [Page.Item] = []
    ) async -> Result<[Page.Item], RunnersError> {
        await call(service, method, request, as: page)
            .flatMapAsync { page in
                let items = found + page.items
                guard let next = page.nextPage, !next.isEmpty, !page.items.isEmpty else {
                    return .success(items)
                }
                return await all(service, method, request.after(next), as: Page.self, found: items)
            }
    }

    static func headers(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Connect-Protocol-Version": "1",
            "User-Agent": "Runners",
        ]
    }

    /// Connect names the error in the body, `{"code": "not_found", "message": …}`, and maps it
    /// onto an HTTP status, which the shared rules read for the rest.
    static func classify(
        tokenHelp: String,
        rejectsToken: @escaping @Sendable (ConnectError) -> Bool
    ) -> @Sendable (HTTPResponse, URL) -> RunnersError {
        { response, url in
            let body = JSONCoding.decode(ConnectError.self, from: response.body).getOrElse { _ in
                ConnectError()
            }
            let message = body.message ?? body.code ?? "HTTP \(response.status)"
            if rejectsToken(body) { return .unauthorized("\(message); \(tokenHelp)") }
            switch body.code ?? "" {
                case "permission_denied": return .forbidden(message)
                case "not_found": return .notFound(message)
                default: return RunnersError(response: response, url: url)
            }
        }
    }
}

/// The error a Connect call answers with.
struct ConnectError: Decodable, Sendable {
    var code: String?
    var message: String?
}

/// A request for one page of a listing.
protocol ConnectPagedRequest: Encodable, Sendable {
    /// The same request for the page this token names.
    func after(_ token: String) -> Self
}

/// One page of a listing.
protocol ConnectPage: Decodable, Sendable {
    associatedtype Item: Sendable
    var items: [Item] { get }
    /// The token for the next page; empty or nil on the last.
    var nextPage: String? { get }
}

/// A proto3 64-bit integer, which JSON carries as a string, `"42"`, though a number is
/// accepted too.
struct ProtoInt64: Codable, Sendable, Hashable {
    let value: Int64

    init(_ value: Int64) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int64.self) {
            value = number
            return
        }
        let raw = try container.decode(String.self)
        guard let number = Int64(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not a 64-bit integer: \(raw)"
            )
        }
        value = number
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(value))
    }
}

/// A proto3 timestamp: RFC 3339, with or without fractions of a second, down to nanoseconds;
/// empty or absent while what it marks hasn't happened.
enum ProtoTime {
    static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return JSONCoding.parseDate(raw)
    }

    /// `2027-01-15T08:00:00Z`
    static func string(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle())
    }
}
