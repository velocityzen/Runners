import Foundation

/// Borrows the token of the GitHub CLI (`gh auth token`), so a signed-in `gh` is all the setup
/// needed.
public enum GHCLI {
    /// - Parameter hostname: The GitHub host, for GitHub Enterprise; `nil` for github.com.
    public static func token(hostname: String? = nil) async -> Result<String, RunnersError> {
        await client(hostname: hostname).token()
    }

    /// `gh auth token`, for one host when it is not github.com.
    public static func client(hostname: String? = nil) -> CLIToken {
        CLIToken(
            "gh",
            ["auth", "token"] + (hostname.map { ["--hostname", $0] } ?? []),
            hint: "set GH_TOKEN or GITHUB_TOKEN, or run `gh auth login`"
        )
    }

    /// The `gh` hostname for an API base URL: `nil` for github.com,
    /// `ghe.example.com` for `https://ghe.example.com/api/v3`,
    /// `acme.ghe.com` for `https://api.acme.ghe.com`.
    public static func hostname(forAPI url: URL) -> String? {
        guard let host = url.host(), host != "api.github.com" else { return nil }
        return host.hasPrefix("api.") ? String(host.dropFirst(4)) : host
    }
}
