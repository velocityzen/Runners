import ArgumentParser
import RunnersKit

@main
struct RunnersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runners",
        abstract:
            "Watch CI runs across every repository of a user, organization or group on \(Providers.builtIn.map(\.name).formatted(.list(type: .and))).",
        subcommands: [StatusCommand.self],
        defaultSubcommand: StatusCommand.self
    )
}
