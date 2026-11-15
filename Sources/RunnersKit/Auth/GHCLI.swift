import FP
import Foundation

/// Borrows the token of the GitHub CLI (`gh auth token`), so a signed-in `gh` is all the setup
/// needed.
public enum GHCLI {
    /// - Parameter hostname: The GitHub host, for GitHub Enterprise; `nil` for github.com.
    public static func token(hostname: String? = nil) async -> Result<String, GitHubError> {
        await run(["gh", "auth", "token"] + (hostname.map { ["--hostname", $0] } ?? []))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap(nonEmpty)
    }

    /// The `gh` hostname for an API base URL: `nil` for github.com,
    /// `ghe.example.com` for `https://ghe.example.com/api/v3`,
    /// `acme.ghe.com` for `https://api.acme.ghe.com`.
    public static func hostname(forAPI url: URL) -> String? {
        guard let host = url.host(), host != "api.github.com" else { return nil }
        return host.hasPrefix("api.") ? String(host.dropFirst(4)) : host
    }

    static func nonEmpty(_ token: String) -> Result<String, GitHubError> {
        token.isEmpty ? .failure(.tokenUnavailable("`gh auth token` printed nothing")) : .success(token)
    }

    /// Runs a command found on `PATH` and returns what it printed.
    static func run(_ arguments: [String]) async -> Result<String, GitHubError> {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: outcome(of: finished, printed: data, arguments: arguments))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure(.tokenUnavailable(error.localizedDescription)))
            }
        }
    }

    static func outcome(of process: Process, printed: Data, arguments: [String]) -> Result<String, GitHubError> {
        process.terminationStatus == 0
            ? .success(String(decoding: printed, as: UTF8.self))
            : .failure(.tokenUnavailable("`\(arguments.joined(separator: " "))` exited with \(process.terminationStatus)"))
    }
}
