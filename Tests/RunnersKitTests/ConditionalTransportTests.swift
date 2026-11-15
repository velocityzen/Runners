import Foundation
import Testing

@testable import RunnersKit

@Suite("Conditional requests")
struct ConditionalTransportTests {
    let url = Fixtures.url("https://api.github.com/repos/octo/repo/actions/runs?status=queued")

    @Test("answers a 304 with the cached body and the fresh headers")
    func notModified() async throws {
        let stub = StubTransport { _, attempt in
            attempt == 0
                ? .raw(200, "first", headers: ["ETag": #"W/"abc""#, "X-RateLimit-Remaining": "10"])
                : .raw(304, headers: ["X-RateLimit-Remaining": "10"])
        }
        let transport = ConditionalTransport(stub)

        let first = try await transport.send(HTTPRequest(url: url)).get()
        let second = try await transport.send(HTTPRequest(url: url)).get()

        #expect(first.body == Data("first".utf8))
        #expect(second.status == 200)
        #expect(second.body == Data("first".utf8))
        #expect(stub.requests[0].headers["If-None-Match"] == nil)
        #expect(stub.requests[1].headers["If-None-Match"] == #"W/"abc""#)
    }

    @Test("replaces the cached body when the resource changed")
    func modified() async throws {
        let stub = StubTransport { _, attempt in
            .raw(200, "version \(attempt)", headers: ["ETag": "\"\(attempt)\""])
        }
        let transport = ConditionalTransport(stub)

        _ = await transport.send(HTTPRequest(url: url))
        let second = try await transport.send(HTTPRequest(url: url)).get()
        _ = await transport.send(HTTPRequest(url: url))

        #expect(second.body == Data("version 1".utf8))
        #expect(stub.requests[2].headers["If-None-Match"] == "\"1\"")
    }

    @Test("does not cache failures")
    func failures() async {
        let stub = StubTransport { _, _ in .raw(500, "oops", headers: ["ETag": "\"x\""]) }
        let transport = ConditionalTransport(stub)

        _ = await transport.send(HTTPRequest(url: url))
        _ = await transport.send(HTTPRequest(url: url))

        #expect(stub.requests[1].headers["If-None-Match"] == nil)
    }
}
