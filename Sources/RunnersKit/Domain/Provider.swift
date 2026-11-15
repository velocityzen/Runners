import Foundation

/// A CI service runners can watch.
///
/// A provider describes itself: what it is called, the settings that configure it, where its
/// token comes from when none is set. It builds the ``CIService`` that maps its API onto the
/// shared domain types. The monitor, the reports and the `runners` CLI know providers only
/// through this protocol; ``Providers/builtIn`` lists the ones this library comes with.
public protocol Provider: Sendable {
    /// Lowercase and stable: what the command line, config files and JSON call it. `github`.
    var id: String { get }

    /// `GitHub`
    var name: String { get }

    /// What the service calls a repository: `("project", "projects")` on GitLab.
    var repositoryTerm: (singular: String, plural: String) { get }

    /// The settings that hold a token, most preferred first.
    var tokenSettings: [ProviderSetting] { get }

    /// The settings that hold the API URL, most preferred first.
    var apiURLSettings: [ProviderSetting] { get }

    /// The public service's API, for when no API URL is set.
    var defaultAPIURL: URL { get }

    /// The API URL a setting's value names, or nil when it names none. By default, an absolute
    /// URL.
    func apiURL(_ value: String, from setting: ProviderSetting) -> URL?

    /// A token for when none is set, or a failure that says how to set one.
    func fallbackToken(apiURL: URL) async -> Result<String, RunnersError>

    /// The client for this service.
    func service(token: String, apiURL: URL, transport: any HTTPTransport) -> any CIService
}

extension Provider {
    public func apiURL(_ value: String, from setting: ProviderSetting) -> URL? {
        URL(string: value).flatMap { $0.host() == nil ? nil : $0 }
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
