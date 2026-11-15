import Foundation

/// Everything that can go wrong while asking a CI service.
public enum RunnersError: LocalizedError, Sendable, Equatable {
    case tokenUnavailable(String)
    /// A setting has a value that cannot be used.
    case configuration(String)
    case invalidURL(String)
    case transport(String)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    /// The quota is spent until it resets.
    case rateLimited(resetAt: Date?)
    /// Too many requests too fast; worth retrying after a wait.
    case throttled(retryAfter: Duration?)
    case server(status: Int, message: String)
    case unexpectedStatus(Int, message: String)
    case decoding(String)
    case encoding(String)
    /// The response cache on disk could not be read or written.
    case cache(String)

    public var errorDescription: String? {
        switch self {
            case .tokenUnavailable(let reason): "No API token: \(reason)"
            case .configuration(let reason): "Configuration: \(reason)"
            case .invalidURL(let raw): "Invalid URL: \(raw)"
            case .transport(let reason): "Network error: \(reason)"
            case .unauthorized(let message): "The token was rejected: \(message)"
            case .forbidden(let message): "Access denied: \(message)"
            case .notFound(let path): "Not found: \(path)"
            case .rateLimited(let resetAt):
                "API rate limit exceeded"
                    + (resetAt.map {
                        "; resets at \($0.formatted(date: .omitted, time: .shortened))"
                    } ?? "")
            case .throttled: "Too many requests at once; try a lower --concurrency."
            case .server(let status, let message): "Server error \(status): \(message)"
            case .unexpectedStatus(let status, let message):
                "Unexpected response \(status): \(message)"
            case .decoding(let reason): "Could not read the response: \(reason)"
            case .encoding(let reason): "Could not encode output: \(reason)"
            case .cache(let reason): "Response cache: \(reason)"
        }
    }

    /// Failures worth retrying: the next attempt may well succeed.
    public var isTransient: Bool {
        switch self {
            case .transport, .server, .throttled: true
            default: false
        }
    }

    /// How long to wait before retrying. Without a `Retry-After`, a minute, as GitHub asks.
    public var retryAfter: Duration? {
        guard case .throttled(let retryAfter) = self else { return nil }
        return retryAfter ?? .seconds(60)
    }
}
