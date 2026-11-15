import ArgumentParser

@main
struct RunnersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runners",
        abstract: "Watch GitHub Actions across every repository of a user or organization.",
        subcommands: [StatusCommand.self],
        defaultSubcommand: StatusCommand.self
    )
}
