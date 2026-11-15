import Configuration
import FP
import Foundation
import RunnersKit
import SystemPackage

/// Where settings are read from, earliest first: the environment, `.env` in the working directory,
/// `.runners` in the working directory (or the file given with `--config`), then `~/.runners`.
struct ConfigSources: Sendable {
    let environment: [String: String]
    let directory: URL
    let home: URL
    /// A config file named on the command line, read instead of `./.runners`. It must exist.
    let configFile: String?

    static func current(configFile: String?) -> ConfigSources {
        ConfigSources(
            environment: ProcessInfo.processInfo.environment,
            directory: URL(
                filePath: FileManager.default.currentDirectoryPath,
                directoryHint: .isDirectory
            ),
            home: FileManager.default.homeDirectoryForCurrentUser,
            configFile: configFile
        )
    }

    func config() async -> Result<Config, RunnersError> {
        await ResultDo<RunnersError>()
            .bindAsync { await Self.environmentFile(directory.appending(path: ".env")) }
            .bind { _ in SettingsFile.read(localFile, required: configFile != nil) }
            .bind { _, _ in SettingsFile.read(home.appending(path: ".runners"), required: false) }
            .map { dotEnv, local, global in
                Config(sources: [
                    ConfigReader(
                        provider: EnvironmentVariablesProvider(environmentVariables: environment)
                    ),
                    ConfigReader(provider: dotEnv),
                    ConfigReader(provider: local),
                    ConfigReader(provider: global),
                ])
            }
    }

    var localFile: URL {
        guard let configFile else { return directory.appending(path: ".runners") }
        return FilePath(configFile).isAbsolute
            ? URL(filePath: configFile) : directory.appending(path: configFile)
    }

    /// A `.env` file: `KEY=value` lines, named like environment variables. A missing one is empty.
    static func environmentFile(
        _ url: URL
    ) async -> Result<EnvironmentVariablesProvider, RunnersError> {
        await Result.fromAsync {
            try await EnvironmentVariablesProvider(
                environmentFilePath: filePath(url),
                allowMissing: true
            )
        }
        .mapError { unreadable(url, $0) }
    }

    static func filePath(_ url: URL) -> FilePath {
        FilePath(url.standardizedFileURL.path(percentEncoded: false))
    }

    static func unreadable(_ url: URL, _ error: any Error) -> RunnersError {
        .configuration(
            "cannot read \(url.standardizedFileURL.path(percentEncoded: false)): \(error)"
        )
    }
}
