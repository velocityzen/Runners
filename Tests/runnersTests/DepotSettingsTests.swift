import Foundation
import RunnersKit
import Testing

@testable import runners

@Suite("Depot CI settings")
struct DepotSettingsTests {
    @Test("reads DEPOT_TOKEN, and DEPOT_API_URL as the depot CLI does")
    func environment() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = [
            "RUNNERS_PROVIDER": "depot-ci",
            "DEPOT_TOKEN": "org-token",
            "DEPOT_API_URL": "https://api.example.com",
        ]
        let settings = try await fixture.settings().get()
        #expect(settings.provider.name == "Depot CI")
        #expect(settings.token == "org-token")
        #expect(settings.apiURL?.absoluteString == "https://api.example.com")
    }

    @Test("defaults to api.depot.dev, and says where to get a token when none is set")
    func defaults() async throws {
        let fixture = try ConfigFixture()
        try fixture.local("provider=depot-ci")
        let settings = try await fixture.settings().get()
        #expect(try await settings.resolvedAPIURL().get().absoluteString == "https://api.depot.dev")
        guard case .failure(.tokenUnavailable(let reason)) = await settings.resolvedToken() else {
            Issue.record("expected tokenUnavailable")
            return
        }
        #expect(reason.contains("organization API token"))
    }
}

@Suite("Depot settings")
struct DepotRunnersSettingsTests {
    @Test("shares DEPOT_TOKEN and DEPOT_API_URL with Depot CI")
    func environment() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = ["RUNNERS_PROVIDER": "depot", "DEPOT_TOKEN": "org-token"]
        let settings = try await fixture.settings().get()
        #expect(settings.provider.name == "Depot")
        #expect(settings.token == "org-token")
        #expect(try await settings.resolvedAPIURL().get().absoluteString == "https://api.depot.dev")
    }
}
