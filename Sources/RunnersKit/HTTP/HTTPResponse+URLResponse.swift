import FP
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

extension HTTPResponse {
    static func from(_ loaded: (Data, URLResponse)) -> Result<HTTPResponse, GitHubError> {
        Result.fromOptional(loaded.1 as? HTTPURLResponse, error: .transport("not an HTTP response"))
            .map { HTTPResponse(status: $0.statusCode, headers: $0.stringHeaders, body: loaded.0) }
    }
}

extension HTTPURLResponse {
    var stringHeaders: [String: String] {
        Dictionary(
            allHeaderFields.compactMap { key, value in
                (key as? String).map { ($0, "\(value)") }
            },
            uniquingKeysWith: { _, last in last }
        )
    }
}
