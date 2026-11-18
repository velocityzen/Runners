import Foundation
import RunnersKit
import Testing

@testable import runners

@Suite("Namespace settings")
struct NamespaceSettingsTests {
    @Test("reads NSC_TOKEN, and NSC_GLOBAL_ENDPOINT as the nsc CLI does")
    func environment() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = [
            "RUNNERS_PROVIDER": "namespace",
            "NSC_TOKEN": "nsct_tenant",
            "NSC_GLOBAL_ENDPOINT": "https://private-api.global.namespaceapis.com",
        ]
        let settings = try await fixture.settings().get()
        #expect(settings.provider.name == "Namespace")
        #expect(settings.token == "nsct_tenant")
        #expect(
            settings.apiURL?.absoluteString == "https://private-api.global.namespaceapis.com"
        )
    }

    @Test("prefers NAMESPACE_TOKEN, takes namespace.token from files, defaults to global")
    func own() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = [
            "RUNNERS_PROVIDER": "namespace", "NSC_TOKEN": "from-nsc", "NAMESPACE_TOKEN": "own",
        ]
        #expect(try await fixture.settings().get().token == "own")

        fixture.environment = ["RUNNERS_PROVIDER": "namespace"]
        try fixture.local("namespace.token=from-file")
        let settings = try await fixture.settings().get()
        #expect(settings.token == "from-file")
        #expect(
            try await settings.resolvedAPIURL().get().absoluteString
                == "https://global.namespaceapis.com"
        )
    }
}
