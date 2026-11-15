import ArgumentParser
import FP
import Foundation
import RunnersKit

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the running, queued and waiting workflow runs of a user or organization."
    )

    @Argument(help: "User or organization to check. Defaults to the user the token belongs to.")
    var owner: String?

    @Option(name: [.customShort("r"), .customLong("repo")], help: "Check only this repository (owner/name). Repeat for more.")
    var repositories: [String] = []

    @Option(name: .shortAndLong, help: "Run status to look for. Repeat for more. Each costs one request per repository with workflows.")
    var status: [ActionStatus] = ActionStatus.active

    @Flag(inversion: .prefixedNo, help: "Fetch the jobs of each run.")
    var jobs = true

    @Flag(help: "List jobs that already passed too, not just their count.")
    var allJobs = false

    @Flag(help: "Include forked repositories.")
    var forks = false

    @Option(name: .shortAndLong, help: "Maximum number of API requests at the same time.")
    var concurrency = 16

    @Flag(help: "Print the snapshot as JSON.")
    var json = false

    @Flag(name: .shortAndLong, help: "Refresh until interrupted.")
    var watch = false

    @Option(name: .shortAndLong, help: "Seconds between refreshes with --watch.")
    var interval = 15

    @Flag(help: "Do not color the output.")
    var noColor = false

    @Option(name: .customLong("api-url"), help: "GitHub API base URL, for GitHub Enterprise. Defaults to $GITHUB_API_URL, then https://api.github.com.")
    var apiURL: String?

    func validate() throws {
        guard (1...32).contains(concurrency) else {
            throw ValidationError("--concurrency must be between 1 and 32.")
        }
        guard interval >= 5 else {
            throw ValidationError("--interval must be at least 5 seconds.")
        }
        guard owner == nil || repositories.isEmpty else {
            throw ValidationError("Pass an owner or --repo, not both.")
        }
        guard repositories.allSatisfy(Self.isFullName) else {
            throw ValidationError("--repo takes owner/name.")
        }
        guard !(json && watch) else {
            throw ValidationError("--json and --watch cannot be combined.")
        }
    }

    func run() async throws {
        let settings = try await Settings.load(apiURL: apiURL).get()
        let monitor = ActionsMonitor(client: GitHubClient(token: settings.token, baseURL: settings.apiURL))
        let output = Output(json: json, colored: !noColor && settings.colorAllowed, showsPassedJobs: allJobs)

        if watch {
            try await Watch(interval: .seconds(interval)) {
                await monitor.snapshot(query).match(output.screen, output.screen)
            }
            .run()
        } else {
            try await monitor.snapshot(query)
                .flatMap(output.render)
                .tap { print($0) }
                .asUnit()
                .get()
        }
    }

    var query: StatusQuery {
        StatusQuery(
            target: target,
            statuses: status,
            includeJobs: jobs,
            includeForks: forks,
            concurrency: concurrency
        )
    }

    var target: StatusQuery.Target {
        if !repositories.isEmpty { return .repositories(repositories) }
        return owner.map(StatusQuery.Target.owner) ?? .authenticatedUser
    }

    static func isFullName(_ name: String) -> Bool {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty }
    }
}
