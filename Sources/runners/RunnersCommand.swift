import ArgumentParser

@main
struct RunnersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runners",
        abstract:
            "Watch CI runs across every repository of a user, organization or group on GitHub and GitLab.",
        subcommands: [StatusCommand.self],
        defaultSubcommand: StatusCommand.self
    )
}
