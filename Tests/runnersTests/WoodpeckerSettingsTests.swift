import Foundation
import RunnersKit
import Testing

@testable import runners

@Suite("Woodpecker settings")
struct WoodpeckerSettingsTests {
    @Test("defaults to ci.codeberg.org's API, and reads public repositories without a token")
    func codeberg() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = ["RUNNERS_PROVIDER": "woodpecker"]
        let settings = try await fixture.settings().get()
        #expect(settings.provider.name == "Woodpecker CI")
        #expect(
            try await settings.resolvedAPIURL().get().absoluteString
                == "https://ci.codeberg.org/api"
        )
        #expect(try await settings.resolvedToken().get() == "")
    }

    @Test("reads WOODPECKER_TOKEN, and WOODPECKER_SERVER as woodpecker-cli does")
    func environment() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = [
            "RUNNERS_PROVIDER": "woodpecker",
            "WOODPECKER_TOKEN": "pat",
            "WOODPECKER_SERVER": "https://ci.example.com",
        ]
        let settings = try await fixture.settings().get()
        #expect(settings.token == "pat")
        #expect(settings.apiURL?.absoluteString == "https://ci.example.com/api")
    }

    @Test(
        "takes the server as a host, a URL or its API URL",
        arguments: ["ci.example.com", "https://ci.example.com", "https://ci.example.com/api"]
    )
    func server(_ server: String) async throws {
        let fixture = try ConfigFixture()
        try fixture.local("provider=woodpecker\nwoodpecker.server=\(server)")
        #expect(
            try await fixture.settings().get().apiURL?.absoluteString
                == "https://ci.example.com/api"
        )
    }
}
