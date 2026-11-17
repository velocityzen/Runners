import ArgumentParser
import FP
import Foundation
import ProcessSignals
import RunnersKit

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the running, queued and waiting CI runs of a user, organization or group."
    )

    @Argument(
        help:
            "User, organization or group to check. Defaults to the user the token belongs to."
    )
    var owner: String?

    @Option(
        name: .shortAndLong,
        help: ArgumentHelp(
            "CI service to ask: \(Providers.builtIn.idList). (default: \(Providers.builtIn[0].id))",
            valueName: "provider"
        ),
        completion: .list(Providers.builtIn.map(\.id))
    )
    var provider: String?

    @Option(
        name: [.customShort("r"), .customLong("repo")],
        help: "Check only this repository (owner/name, or group/…/name). Repeat for more."
    )
    var repositories: [String] = []

    @Option(
        name: .shortAndLong,
        help:
            "Run status to show. Repeat for more. (default: all active)"
    )
    var status: [RunStatus] = []

    @Flag(inversion: .prefixedNo, help: "Fetch the jobs of each run. (default: --jobs)")
    var jobs: Bool?

    @Flag(
        inversion: .prefixedNo,
        help: "List jobs that already passed too, not just their count. (default: --no-all-jobs)"
    )
    var allJobs: Bool?

    @Flag(inversion: .prefixedNo, help: "Include forked repositories. (default: --no-forks)")
    var forks: Bool?

    @Option(
        name: .shortAndLong,
        help: "Maximum number of API requests at the same time, 1–32. (default: 16)"
    )
    var concurrency: Int?

    @Flag(help: "List the runners and what they are doing, instead of the runs.")
    var runners = false

    @Flag(help: "Print the snapshot as JSON.")
    var json = false

    @Flag(name: .shortAndLong, help: "Refresh until interrupted.")
    var watch = false

    @Option(
        name: .shortAndLong,
        help: "Seconds between refreshes with --watch, at least 5. (default: 15)"
    )
    var interval: Int?

    @Flag(
        inversion: .prefixedNo,
        help: "Color the output. (default: when printing to a terminal and NO_COLOR is unset)"
    )
    var color: Bool?

    @Flag(
        inversion: .prefixedNo,
        help:
            "Report status to the terminal with the Program Status Protocol (OSC 7501). (default: --program-status)"
    )
    var programStatus: Bool?

    @Flag(
        inversion: .prefixedNo,
        help:
            "Keep API responses between runs, so unchanged ones cost no quota. (default: --cache)"
    )
    var cache: Bool?

    @Option(
        name: .customLong("api-url"),
        help: "API base URL, for a self-hosted instance. (default: the provider's public service)"
    )
    var apiURL: String?

    @Option(name: .customLong("config"), help: "Settings file to read instead of ./.runners.")
    var configFile: String?

    func validate() throws {
        if let provider, Providers.builtIn.named(provider) == nil {
            throw ValidationError("--provider takes \(Providers.builtIn.idList).")
        }
        if let concurrency, !(1...32).contains(concurrency) {
            throw ValidationError("--concurrency must be between 1 and 32.")
        }
        if let interval, interval < 5 {
            throw ValidationError("--interval must be at least 5 seconds.")
        }
        guard owner == nil || repositories.isEmpty else {
            throw ValidationError("Pass an owner or --repo, not both.")
        }
        guard !(json && watch) else {
            throw ValidationError("--json and --watch cannot be combined.")
        }
    }

    func run() async throws {
        let settings = try await Settings.load(
            overrides,
            configFile: configFile,
            providers: Providers.builtIn
        )
        .get()

        let cache = ResponseCache.load(enabled: settings.cachesResponses)
        let session = StatusSession(
            monitor: RunsMonitor(service: try await settings.service(cache: cache.cache).get()),
            settings: settings,
            output: Output(
                json: json,
                colored: settings.display.colored,
                showsPassedJobs: settings.display.showsPassedJobs
            ),
            status: TerminalStatus(enabled: settings.display.reportsProgramStatus),
            cache: cache,
            listsRunners: runners
        )
        let watches = watch
        let signals = await processSignals([SIGINT, SIGTERM])

        // Whichever ends first: the session, or a signal. `withAny` cancels the other and
        // returns once it stops, so the session cleans up after a signal. A signal stream that
        // ends without a signal fails, and a failure never wins.
        let ending = await withAny(
            await .success(watches ? session.watch() : session.check()),
            await Result.fromOptional(signals.first { _ in true }, error: NoSignal())
                .map { .interrupted(signal: $0) }
        )

        // Only the signals can fail, so the session always gives a value.
        switch ending.getOrElse({ _ in .finished(.success(())) }) {
            case .finished(let result):
                try result.get()
            case .interrupted(let signal):
                session.status.send(.stopped)
                throw ExitCode(128 + signal)
        }
    }

    var overrides: Overrides {
        Overrides(
            provider: provider,
            owner: owner,
            repositories: repositories,
            statuses: status,
            jobs: jobs,
            allJobs: allJobs,
            forks: forks,
            concurrency: concurrency,
            interval: interval,
            color: color,
            programStatus: programStatus,
            cache: cache,
            apiURL: apiURL
        )
    }
}

/// The signals stream ended without a signal: it was cancelled, or could not subscribe.
private struct NoSignal: Error {}
