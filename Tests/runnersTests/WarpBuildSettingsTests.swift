import Foundation
import RunnersKit
import Testing

@testable import runners

@Suite("WarpBuild settings")
struct WarpBuildSettingsTests {
    @Test("reads WARPBUILD_API_KEY and WARPBUILD_API_URL")
    func environment() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = [
            "RUNNERS_PROVIDER": "warpbuild",
            "WARPBUILD_API_KEY": "wkey-env",
            "WARPBUILD_API_URL": "https://api.example.com/api/v1",
        ]
        let settings = try await fixture.settings().get()
        #expect(settings.provider.name == "WarpBuild")
        #expect(settings.token == "wkey-env")
        #expect(settings.apiURL?.absoluteString == "https://api.example.com/api/v1")
    }

    @Test("defaults to api.warpbuild.com, and says where to get a key when none is set")
    func defaults() async throws {
        let fixture = try ConfigFixture()
        try fixture.local("provider=warpbuild")
        let settings = try await fixture.settings().get()
        #expect(
            try await settings.resolvedAPIURL().get().absoluteString
                == "https://api.warpbuild.com/api/v1"
        )
        guard case .failure(.tokenUnavailable(let reason)) = await settings.resolvedToken() else {
            Issue.record("expected tokenUnavailable")
            return
        }
        #expect(reason.contains("WARPBUILD_API_KEY"))

        try fixture.local("provider=warpbuild\nwarpbuild.api_key=wkey-file")
        #expect(try await fixture.settings().get().token == "wkey-file")
    }
}
