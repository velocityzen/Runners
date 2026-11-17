import FP
import Foundation
import RunnersKit

/// Everything a status check needs: the command line first, then the config, then defaults.
struct Settings: Sendable {
    let provider: any Provider
    /// The configured API URL; nil leaves it to the provider's fallback.
    let apiURL: URL?
    /// The configured token; nil leaves it to the provider's fallback.
    let token: String?
    let query: StatusQuery
    let display: Display
    /// Whether to keep API responses on disk between runs.
    let cachesResponses: Bool

    /// How results are shown and reported.
    struct Display: Sendable, Equatable {
        let showsPassedJobs: Bool
        /// Seconds between snapshots with `--watch`.
        let interval: Int
        let colored: Bool
        /// Whether to report to the terminal with the Program Status Protocol.
        let reportsProgramStatus: Bool
    }

    /// The settings for one of `providers`, the first being the default.
    static func load(
        _ given: Overrides,
        configFile: String?,
        providers: [any Provider]
    ) async -> Result<Settings, RunnersError> {
        await ConfigSources.current(configFile: configFile)
            .config(keys: SettingKeys(providers: providers))
            .flatMap {
                resolve(
                    given,
                    from: $0,
                    providers: providers,
                    isTerminal: isatty(STDOUT_FILENO) != 0
                )
            }
    }

    static func resolve(
        _ given: Overrides,
        from config: Config,
        providers: [any Provider],
        isTerminal: Bool
    ) -> Result<Settings, RunnersError> {
        ResultDo<RunnersError>()
            .bind { providers.choice(given.provider, in: config) }
            .bind { provider in provider.apiURL(given.apiURL, in: config) }
            .bind { provider, _ in provider.token(in: config) }
            .bind { provider, _, _ in query(given, config, provider: provider) }
            .bind { _, _, _, _ in display(given, config, isTerminal: isTerminal) }
            .bind { _, _, _, _, _ in config.flag(given.cache, .cache, default: true) }
            .map { provider, apiURL, token, query, display, cachesResponses in
                Settings(
                    provider: provider,
                    apiURL: apiURL,
                    token: token,
                    query: query,
                    display: display,
                    cachesResponses: cachesResponses
                )
            }
    }

    static func display(
        _ given: Overrides,
        _ config: Config,
        isTerminal: Bool
    ) -> Result<Display, RunnersError> {
        flatten(
            config.flag(given.allJobs, .allJobs, default: false),
            config.number(given.interval, .interval, default: 15, in: 5...86_400),
            colored(given, config, isTerminal: isTerminal),
            config.flag(given.programStatus, .programStatus, default: true)
        )
        .map { allJobs, interval, colored, programStatus in
            Display(
                showsPassedJobs: allJobs,
                interval: interval,
                colored: colored,
                reportsProgramStatus: programStatus
            )
        }
    }

    /// The service to ask, with the configured API URL and token, or else the provider's
    /// fallbacks.
    func service(cache: ETagCache) async -> Result<any CIService, RunnersError> {
        let transport = ConditionalTransport(URLSessionTransport(), cache: cache)
        let provider = provider
        return await resolvedAPIURL()
            .flatMapAsync { apiURL in
                await resolvedToken(apiURL: apiURL)
                    .map { provider.service(token: $0, apiURL: apiURL, transport: transport) }
            }
    }

    func resolvedAPIURL() async -> Result<URL, RunnersError> {
        guard let apiURL else { return await provider.fallbackAPIURL() }
        return .success(apiURL)
    }

    func resolvedToken() async -> Result<String, RunnersError> {
        await resolvedAPIURL().flatMapAsync { await resolvedToken(apiURL: $0) }
    }

    func resolvedToken(apiURL: URL) async -> Result<String, RunnersError> {
        guard let token else { return await provider.fallbackToken(apiURL: apiURL) }
        return .success(token)
    }
}

extension Settings {
    static func query(
        _ given: Overrides,
        _ config: Config,
        provider: any Provider
    ) -> Result<StatusQuery, RunnersError> {
        flatten(
            given.target.map { target(given: $0, provider: provider) }
                ?? target(config, provider: provider),
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

    /// The command line's owner, or its repositories, named as the provider names them.
    static func target(
        given: StatusQuery.Target,
        provider: any Provider
    ) -> Result<StatusQuery.Target, RunnersError> {
        guard case .repositories(let names) = given else { return .success(given) }
        return names.traverse { name in
            provider.isRepositoryName(name)
                ? .success(name)
                : .failure(
                    .configuration(
                        "--repo is \"\(name)\", expected \(provider.repositoryNameFormat)"
                    )
                )
        }
        .map(StatusQuery.Target.repositories)
    }

    /// Owner and repositories go together: the first source that sets either decides both.
    static func target(
        _ config: Config,
        provider: any Provider
    ) -> Result<StatusQuery.Target, RunnersError> {
        config.sources.lazy
            .map { (owner: $0.text(.owner), repositories: $0.list(.repositories)) }
            .first { $0.owner != nil || !$0.repositories.isEmpty }
            .map { target(owner: $0.owner, repositories: $0.repositories, provider: provider) }
            ?? .success(.authenticatedUser)
    }

    static func target(
        owner: String?,
        repositories: [String],
        provider: any Provider
    ) -> Result<StatusQuery.Target, RunnersError> {
        if owner != nil, !repositories.isEmpty {
            return .failure(
                .configuration("set \(SettingKey.owner) or \(SettingKey.repositories), not both")
            )
        }
        if let owner { return .success(.owner(owner)) }
        return repositories.traverse { repositoryName($0, provider: provider) }
            .map(StatusQuery.Target.repositories)
    }

    static func repositoryName(
        _ name: String,
        provider: any Provider
    ) -> Result<String, RunnersError> {
        provider.isRepositoryName(name)
            ? .success(name)
            : .failure(
                SettingKey.repositories.invalid(name, expected: provider.repositoryNameFormat)
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
