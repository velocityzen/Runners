import FP
import Foundation
internal import Subprocess

/// A command line client that prints an API token, like `gh auth token`, so a signed-in CLI is
/// all the setup a provider needs.
///
/// The command is found on `PATH`, and what it prints, trimmed, is the token. When there is
/// none, the failure says why (not installed, exited with a code and the first line it wrote
/// to standard error, stopped by a signal, printed too much or nothing at all), then `hint`.
public struct CLIToken: Sendable, Hashable {
    /// The most a command may print, on each of standard output and standard error. A token is
    /// far shorter; more is a command that does something else.
    public static let outputLimit = 64 * 1024

    public let command: String
    public let arguments: [String]
    /// How to give a token instead, such as "set GH_TOKEN or GITHUB_TOKEN, or run
    /// `gh auth login`".
    public let hint: String

    public init(_ command: String, _ arguments: [String] = [], hint: String) {
        self.command = command
        self.arguments = arguments
        self.hint = hint
    }

    /// The token the command prints.
    public func token() async -> Result<String, RunnersError> {
        await printed()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap {
                $0.isEmpty ? .failure(unavailable("\(commandLine) printed nothing")) : .success($0)
            }
    }

    /// What the command printed, when it exited with 0.
    func printed() async -> Result<String, RunnersError> {
        await Result.fromAsync {
            let run = try await Subprocess.run(
                .name(command),
                arguments: Arguments(arguments),
                output: .string(limit: Self.outputLimit),
                error: .string(limit: Self.outputLimit)
            )
            return Finished(
                status: run.terminationStatus,
                output: run.standardOutput,
                errorOutput: run.standardError
            )
        }
        .mapError { unavailable(reason(for: $0)) }
        .flatMap { finished in
            finished.status.isSuccess
                ? .success(finished.output)
                : .failure(unavailable(ending(of: finished)))
        }
    }

    /// The command as typed in a shell, quoted for a message.
    var commandLine: String {
        "`" + ([command] + arguments).joined(separator: " ") + "`"
    }

    func unavailable(_ reason: String) -> RunnersError {
        .tokenUnavailable("\(reason); \(hint)")
    }

    /// Why a command that did not exit with 0 gave no token.
    func ending(of finished: Finished) -> String {
        switch finished.status {
            case .exited(let code):
                "\(commandLine) exited with \(code)" + Self.complaint(in: finished.errorOutput)
            #if !os(Windows)
                case .signaled(let signal):
                    "\(commandLine) was stopped by signal \(signal)"
            #endif
        }
    }

    /// Why a command could not run at all.
    func reason(for error: any Error) -> String {
        guard let error = error as? SubprocessError else {
            return "\(commandLine) could not run: \(error.localizedDescription)"
        }
        return switch error.code {
            case .executableNotFound: "`\(command)` is not installed or not on PATH"
            case .outputLimitExceeded: "\(commandLine) printed more than \(Self.outputLimit) bytes"
            default: "\(commandLine) could not run: \(error)"
        }
    }

    /// The first line a command wrote to standard error, such as gh's "no oauth token found for
    /// github.com", after a colon; nothing when it wrote none.
    static func complaint(in errorOutput: String) -> String {
        errorOutput.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
            .map { ": " + $0.prefix(200) } ?? ""
    }

    /// How a command that ran ended, and what it wrote.
    struct Finished: Sendable {
        let status: TerminationStatus
        let output: String
        let errorOutput: String
    }
}
