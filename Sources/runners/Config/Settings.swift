import FP
import Foundation
import RunnersKit

/// Everything a status check needs: the command line first, then the config, then defaults.
struct Settings: Sendable {
    let provider: Provider
    let apiURL: URL
    /// The configured token; nil leaves it to the provider's fallback, such as `gh`.
    let token: String?
    let query: StatusQuery
    let showsPassedJobs: Bool
    let interval: Int
    let colored: Bool

    static func load(
        _ given: Overrides,
        configFile: String?
    ) async -> Result<Settings, RunnersError> {
        await ConfigSources.current(configFile: configFile)
            .config()
            .flatMap { resolve(given, from: $0, isTerminal: isatty(STDOUT_FILENO) != 0) }
    }

    static func resolve(
        _ given: Overrides,
        from config: Config,
        isTerminal: Bool
    ) -> Result<Settings, RunnersError> {
        ResultDo<RunnersError>()
            .bind { provider(given, config) }
            .bind { provider in provider.apiURL(given.apiURL, in: config) }
            .bind { _, _ in query(given, config) }
            .bind { _, _, _ in config.flag(given.allJobs, .allJobs, default: false) }
            .bind { _, _, _, _ in
                config.number(given.interval, .interval, default: 15, in: 5...86_400)
            }
            .bind { _, _, _, _, _ in colored(given, config, isTerminal: isTerminal) }
            .map { provider, apiURL, query, allJobs, interval, colored in
                Settings(
                    provider: provider,
                    apiURL: apiURL,
                    token: provider.token(in: config),
                    query: query,
                    showsPassedJobs: allJobs,
                    interval: interval,
                    colored: colored
                )
            }
    }

    /// The service to ask, with the configured token or else the provider's fallback.
    func service() async -> Result<any CIService, RunnersError> {
        await resolvedToken().map { provider.service(token: $0, apiURL: apiURL) }
    }

    func resolvedToken() async -> Result<String, RunnersError> {
        guard let token else { return await provider.fallbackToken(apiURL: apiURL) }
        return .success(token)
    }
}

extension Settings {
    static func provider(_ given: Overrides, _ config: Config) -> Result<Provider, RunnersError> {
        config.value(given.provider, .provider, default: .github, expected: "github or gitlab") {
            Provider(rawValue: $0.lowercased())
        }
    }

    static func query(_ given: Overrides, _ config: Config) -> Result<StatusQuery, RunnersError> {
        flatten(
            given.target.map(Result.success) ?? target(config),
            statuses(given, config),
            config.flag(given.jobs, .jobs, default: true),
            config.flag(given.forks, .forks, default: false),
            config.number(given.concurrency, .concurrency, default: 16, in: 1...32)
        )
        .map { target, statuses, jobs, forks, concurrency in
            StatusQuery(
                target: target,
                statuses: statuses,
                includeJobs: jobs,
                includeForks: forks,
                concurrency: concurrency
            )
        }
    }

    /// Owner and repositories go together: the first source that sets either decides both.
    static func target(_ config: Config) -> Result<StatusQuery.Target, RunnersError> {
        config.sources.lazy
            .map { (owner: $0.text(.owner), repositories: $0.list(.repositories)) }
            .first { $0.owner != nil || !$0.repositories.isEmpty }
            .map { target(owner: $0.owner, repositories: $0.repositories) }
            ?? .success(.authenticatedUser)
    }

    static func target(
        owner: String?,
        repositories: [String]
    ) -> Result<StatusQuery.Target, RunnersError> {
        if owner != nil, !repositories.isEmpty {
            return .failure(
                .configuration("set \(SettingKey.owner) or \(SettingKey.repositories), not both")
            )
        }
        if let owner { return .success(.owner(owner)) }
        return repositories.traverse(fullName).map(StatusQuery.Target.repositories)
    }

    static func fullName(_ name: String) -> Result<String, RunnersError> {
        StatusQuery.Target.isFullName(name)
            ? .success(name)
            : .failure(
                SettingKey.repositories.invalid(
                    name,
                    expected: "owner/name, or group/…/project on GitLab"
                )
            )
    }

    static func statuses(_ given: Overrides, _ config: Config) -> Result<[RunStatus], RunnersError>
    {
        let configured = given.statuses.isEmpty ? config.list(.status) : []
        guard !configured.isEmpty else {
            return .success(given.statuses.isEmpty ? RunStatus.active : given.statuses)
        }
        return configured.traverse(status)
    }

    static func status(_ raw: String) -> Result<RunStatus, RunnersError> {
        .fromOptional(
            RunStatus(argument: raw.lowercased()),
            error: SettingKey.status.invalid(
                raw,
                expected: RunStatus.allValueStrings.formatted(.list(type: .or))
            )
        )
    }

    /// `NO_COLOR` and a pipe turn color off unless the command line or the config asks for it.
    static func colored(
        _ given: Overrides,
        _ config: Config,
        isTerminal: Bool
    ) -> Result<Bool, RunnersError> {
        config.flag(given.color, .color, default: isTerminal && config.text(.noColor) == nil)
    }

    /// An absolute URL, or a failure naming what was given.
    static func url(_ raw: String) -> Result<URL, RunnersError> {
        .fromOptional(
            URL(string: raw).flatMap { $0.host() == nil ? nil : $0 },
            error: .invalidURL(raw)
        )
    }
}
