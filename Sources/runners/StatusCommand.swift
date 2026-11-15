import ArgumentParser
import FP
import Foundation
import RunnersKit

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the running, queued and waiting CI runs of a user, organization or group."
    )

    @Argument(
        help:
            "User, organization or GitLab group to check. Defaults to the user the token belongs to."
    )
    var owner: String?

    @Option(name: .shortAndLong, help: "CI service to ask. (default: github)")
    var provider: Provider?

    @Option(
        name: [.customShort("r"), .customLong("repo")],
        help: "Check only this repository (owner/name; GitLab: group/…/project). Repeat for more."
    )
    var repositories: [String] = []

    @Option(
        name: .shortAndLong,
        help:
            "Run status to show. Repeat for more. On GitHub each costs a request per repository. (default: all active)"
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

    @Option(
        name: .customLong("api-url"),
        help: "API base URL, for GitHub Enterprise or self-managed GitLab."
    )
    var apiURL: String?

    @Option(name: .customLong("config"), help: "Settings file to read instead of ./.runners.")
    var configFile: String?

    func validate() throws {
        if let concurrency, !(1...32).contains(concurrency) {
            throw ValidationError("--concurrency must be between 1 and 32.")
        }
        if let interval, interval < 5 {
            throw ValidationError("--interval must be at least 5 seconds.")
        }
        guard owner == nil || repositories.isEmpty else {
            throw ValidationError("Pass an owner or --repo, not both.")
        }
        guard repositories.allSatisfy(StatusQuery.Target.isFullName) else {
            throw ValidationError(
                "--repo takes the full name: owner/name, or group/…/project on GitLab."
            )
        }
        guard !(json && watch) else {
            throw ValidationError("--json and --watch cannot be combined.")
        }
    }

    func run() async throws {
        let settings = try await Settings.load(overrides, configFile: configFile).get()
        let monitor = RunsMonitor(service: try await settings.service().get())
        let output = Output(
            json: json,
            colored: settings.colored,
            showsPassedJobs: settings.showsPassedJobs
        )

        if watch {
            let screens =
                monitor
                .watch(settings.query, every: .seconds(settings.interval))
                .map(output.screen(for:))

            for await screen in screens {
                Screen.redraw(screen)
            }
        } else {
            try await monitor.snapshot(settings.query)
                .flatMap(output.render)
                .tap { print($0) }
                .asUnit()
                .get()
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
            apiURL: apiURL
        )
    }
}
