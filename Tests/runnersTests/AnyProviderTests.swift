import Foundation
import RunnersKit
import Testing

@testable import runners

/// The CLI knows providers only through the protocol, so a new one needs no change to it.
@Suite("Any provider")
struct AnyProviderTests {
    /// A provider the CLI has never heard of.
    struct Forge: Provider {
        let id = "forge"
        let name = "Forge"
        let repositoryTerm = (singular: "repo", plural: "repos")
        let tokenSettings: [ProviderSetting] = [
            .environment("forge.ci_token"), .setting("forge.token"),
        ]
        let apiURLSettings: [ProviderSetting] = [.setting("forge.host")]

        func fallbackAPIURL() async -> Result<URL, RunnersError> {
            .success(URL(filePath: "/forge"))
        }

        func apiURL(_ value: String, from setting: ProviderSetting) -> URL? {
            URL(string: "https://\(value)/api")
        }

        func fallbackToken(apiURL: URL) async -> Result<String, RunnersError> {
            .failure(.tokenUnavailable("set FORGE_TOKEN"))
        }

        func service(token: String, apiURL: URL, transport: any HTTPTransport) -> any CIService {
            GitHubService(token: token, baseURL: apiURL, transport: transport)
        }
    }

    func fixture(_ providers: [any Provider] = Providers.builtIn + [Forge()]) throws
        -> ConfigFixture
    {
        let fixture = try ConfigFixture()
        fixture.providers = providers
        return fixture
    }

    @Test("reads the provider's own settings from files, and parses its API URL its way")
    func settings() async throws {
        let fixture = try fixture()
        try fixture.local("provider=forge\nforge.token=from-file\nforge.host=forge.example.com")
        let settings = try await fixture.settings().get()
        #expect(settings.provider.id == "forge")
        #expect(settings.token == "from-file")
        #expect(settings.apiURL == URL(string: "https://forge.example.com/api"))
    }

    @Test("takes another tool's variable from the environment only")
    func environmentOnly() async throws {
        let fixture = try fixture()
        fixture.environment = ["RUNNERS_PROVIDER": "forge", "FORGE_CI_TOKEN": "from-ci"]
        try fixture.local("forge.token=from-file")
        let settings = try await fixture.settings().get()
        #expect(settings.token == "from-ci")
        #expect(settings.apiURL == nil)
        #expect(try await settings.resolvedAPIURL().get() == URL(filePath: "/forge"))
        try fixture.local("forge.ci_token=x")
        let problem = try #require(await fixture.settings().configurationProblem)
        #expect(problem.contains("unknown setting \"forge.ci_token\""))
        #expect(
            problem.hasSuffix(
                "github.token, github.api_url, gitlab.token, gitlab.host, forgejo.token, "
                    + "forgejo.host, woodpecker.token, woodpecker.server, aws.access_key_id, "
                    + "aws.secret_access_key, aws.session_token, aws.region, forge.token, forge.host"
            )
        )
    }

    @Test("defaults to the first provider, and names them all when one is unknown")
    func choice() async throws {
        let fixture = try fixture([Forge(), GitHubProvider()])
        #expect(try await fixture.settings().get().provider.id == "forge")
        var given = Overrides()
        given.provider = "GitHub"
        #expect(try await fixture.settings(given).get().provider.id == "github")
        given.provider = "nope"
        let problem = try #require(await fixture.settings(given).configurationProblem)
        #expect(problem == "provider (RUNNERS_PROVIDER) is \"nope\", expected forge or github")
    }

    @Test("leaves the token to the provider when none is set")
    func fallback() async throws {
        var given = Overrides()
        given.provider = "forge"
        let settings = try await fixture().settings(given).get()
        let token = await settings.resolvedToken()
        #expect(token == .failure(.tokenUnavailable("set FORGE_TOKEN")))
    }
}
