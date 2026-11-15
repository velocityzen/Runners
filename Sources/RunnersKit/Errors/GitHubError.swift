import Foundation

/// Everything that can go wrong while talking to GitHub.
public enum GitHubError: LocalizedError, Sendable, Equatable {
    case tokenUnavailable(String)
    case invalidURL(String)
    case transport(String)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case rateLimited(resetAt: Date?)
    case secondaryRateLimited(retryAfter: Duration?)
    case server(status: Int, message: String)
    case unexpectedStatus(Int, message: String)
    case decoding(String)
    case encoding(String)

    public var errorDescription: String? {
        switch self {
            case .tokenUnavailable(let reason):
                "No GitHub token: \(reason). Set GH_TOKEN or GITHUB_TOKEN, or sign in with `gh auth login`."
            case .invalidURL(let raw): "Invalid URL: \(raw)"
            case .transport(let reason): "Network error: \(reason)"
            case .unauthorized(let message): "GitHub rejected the token: \(message)"
            case .forbidden(let message): "GitHub denied access: \(message)"
            case .notFound(let path): "Not found on GitHub: \(path)"
            case .rateLimited(let resetAt):
                "GitHub API rate limit exceeded"
                    + (resetAt.map { "; resets at \($0.formatted(date: .omitted, time: .shortened))" } ?? "")
            case .secondaryRateLimited: "GitHub secondary rate limit hit; try fewer concurrent requests."
            case .server(let status, let message): "GitHub server error \(status): \(message)"
            case .unexpectedStatus(let status, let message): "Unexpected GitHub response \(status): \(message)"
            case .decoding(let reason): "Could not read GitHub's response: \(reason)"
            case .encoding(let reason): "Could not encode output: \(reason)"
        }
    }

    /// Failures worth retrying: the next attempt may well succeed.
    public var isTransient: Bool {
        switch self {
            case .transport, .server, .secondaryRateLimited: true
            default: false
        }
    }

    /// The wait GitHub asks for before retrying. Without a `Retry-After`, GitHub asks clients
    /// that hit the secondary rate limit to wait at least a minute.
    public var retryAfter: Duration? {
        guard case .secondaryRateLimited(let retryAfter) = self else { return nil }
        return retryAfter ?? .seconds(60)
    }
}
