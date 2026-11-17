import Foundation
import RunnersKit
import Testing

@testable import runners

@Suite("Forgejo settings")
struct ForgejoSettingsTests {
    @Test("defaults to Codeberg, and reads public repositories without a token")
    func codeberg() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = ["RUNNERS_PROVIDER": "forgejo"]
        let settings = try await fixture.settings().get()
        #expect(settings.provider.name == "Forgejo Actions")
        #expect(
            try await settings.resolvedAPIURL().get().absoluteString
                == "https://codeberg.org/api/v1"
        )
        #expect(try await settings.resolvedToken().get() == "")
    }

    @Test("takes FORGEJO_TOKEN over CODEBERG_TOKEN, and CODEBERG_TOKEN from the environment only")
    func token() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = [
            "RUNNERS_PROVIDER": "forgejo", "CODEBERG_TOKEN": "codeberg", "FORGEJO_TOKEN": "forgejo",
        ]
        #expect(try await fixture.settings().get().token == "forgejo")
        fixture.environment = ["RUNNERS_PROVIDER": "forgejo", "CODEBERG_TOKEN": "codeberg"]
        #expect(try await fixture.settings().get().token == "codeberg")
        try fixture.local("codeberg.token=x")
        let problem = try #require(await fixture.settings().configurationProblem)
        #expect(problem.contains("unknown setting \"codeberg.token\""))
    }

    @Test(
        "takes a host, a URL or the API URL for another instance",
        arguments: [
            "git.example.com", "https://git.example.com", "https://git.example.com/api/v1",
        ]
    )
    func host(_ host: String) async throws {
        let fixture = try ConfigFixture()
        try fixture.local("provider=forgejo\nforgejo.host=\(host)\nforgejo.token=t")
        #expect(
            try await fixture.settings().get().apiURL?.absoluteString
                == "https://git.example.com/api/v1"
        )
    }
}
