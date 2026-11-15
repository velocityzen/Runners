import Foundation
import RunnersKit

@testable import runners

/// A working directory and a home directory on disk, removed when the fixture goes away.
final class ConfigFixture {
    let root: URL
    var environment: [String: String] = [:]
    var configFile: String?

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "runners-tests-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var project: URL { root.appending(path: "project") }
    var home: URL { root.appending(path: "home") }

    func write(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// `./.runners`
    func local(_ yaml: String) throws {
        try write(yaml, to: project.appending(path: ".runners"))
    }

    /// `~/.runners`
    func global(_ yaml: String) throws {
        try write(yaml, to: home.appending(path: ".runners"))
    }

    /// `./.env`
    func dotEnv(_ lines: String) throws {
        try write(lines, to: project.appending(path: ".env"))
    }

    var sources: ConfigSources {
        ConfigSources(
            environment: environment,
            directory: project,
            home: home,
            configFile: configFile
        )
    }

    func config() async -> Result<Config, RunnersError> {
        await sources.config()
    }

    func settings(
        _ given: Overrides = Overrides(),
        isTerminal: Bool = true
    ) async -> Result<Settings, RunnersError> {
        await config().flatMap { Settings.resolve(given, from: $0, isTerminal: isTerminal) }
    }
}

extension Result where Failure == RunnersError {
    /// The message of a configuration failure.
    var configurationProblem: String? {
        guard case .failure(.configuration(let message)) = self else { return nil }
        return message
    }
}
