import Foundation

/// A CI service runners can watch.
///
/// A provider describes itself: what it is called, the settings that configure it, where its
/// token and API URL come from when none is set. It builds the ``CIService`` that maps its API
/// onto the shared domain types. The monitor, the reports and the `runners` CLI know providers
/// only through this protocol; ``Providers/builtIn`` lists the ones this library comes with.
public protocol Provider: Sendable {
    /// Lowercase and stable: what the command line, config files and JSON call it. `github`.
    var id: String { get }

    /// `GitHub`
    var name: String { get }

    /// What the service calls a repository: `("project", "projects")` on GitLab.
    var repositoryTerm: (singular: String, plural: String) { get }

    /// The settings that hold a token, most preferred first. For a provider whose credentials
    /// span several settings, all of them.
    var tokenSettings: [ProviderSetting] { get }

    /// The settings that hold the API URL, most preferred first.
    var apiURLSettings: [ProviderSetting] { get }

    /// The token the settings hold, or nil when they hold none and ``fallbackToken(apiURL:)``
    /// should give one. `value` gives the first value set among the settings it is passed,
    /// earlier ones first. By default, the first of ``tokenSettings`` that is set.
    func token(from value: ([ProviderSetting]) -> String?) -> Result<String?, RunnersError>

    /// The API URL a setting's value names, or nil when it names none. By default, an absolute
    /// URL.
    func apiURL(_ value: String, from setting: ProviderSetting) -> URL?

    /// What one of ``apiURLSettings`` takes, for a message: `a URL` by default.
    func apiURLFormat(of setting: ProviderSetting) -> String

    /// The API URL for when none is set: the public service's, or one that another tool is
    /// configured with.
    func fallbackAPIURL() async -> Result<URL, RunnersError>

    /// A token for when none is set, or a failure that says how to set one.
    func fallbackToken(apiURL: URL) async -> Result<String, RunnersError>

    /// Whether `name` names one repository the way `--repo` takes it. By default a full name:
    /// `owner/name`, or `group/…/name` where groups nest.
    func isRepositoryName(_ name: String) -> Bool

    /// What `--repo` takes, for a message: `owner/name, or group/…/name`.
    var repositoryNameFormat: String { get }

    /// The client for this service.
    func service(token: String, apiURL: URL, transport: any HTTPTransport) -> any CIService
}

extension Provider {
    public func token(from value: ([ProviderSetting]) -> String?) -> Result<String?, RunnersError> {
        .success(value(tokenSettings))
    }

    public func apiURL(_ value: String, from setting: ProviderSetting) -> URL? {
        URL(string: value).flatMap { $0.host() == nil ? nil : $0 }
    }

    public func apiURLFormat(of setting: ProviderSetting) -> String {
        "a URL"
    }

    public func isRepositoryName(_ name: String) -> Bool {
        StatusQuery.Target.isFullName(name)
    }

    public var repositoryNameFormat: String {
        "owner/name, or group/…/name"
    }
}

/// A setting a provider reads, named in lowercase with dots: `github.token`. The environment
/// spells it in capitals with underscores: `GITHUB_TOKEN`.
public struct ProviderSetting: Sendable, Hashable {
    public let name: String
    /// Whether `.runners` files take it. Names other tools set in the environment, such as
    /// `GH_TOKEN`, are read from the environment only.
    public let inFiles: Bool

    /// A setting of this provider's own: files and the environment both take it.
    public static func setting(_ name: String) -> ProviderSetting {
        ProviderSetting(name: name, inFiles: true)
    }

    /// Another tool's environment variable, such as `gh.token` for `GH_TOKEN`.
    public static func environment(_ name: String) -> ProviderSetting {
        ProviderSetting(name: name, inFiles: false)
    }
}
