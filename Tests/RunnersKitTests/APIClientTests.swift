import FPRetry
import Foundation
import Testing

@testable import RunnersKit

@Suite("API client")
struct APIClientTests {
    let base = Fixtures.url("https://gitlab.example.com/api/v4")

    func client(_ stub: StubTransport, base: URL? = nil) -> APIClient {
        APIClient(
            baseURL: base ?? self.base,
            headers: ["Authorization": "Bearer t0ken"],
            transport: stub,
            retryPolicy: .limitRetries(2)
        )
    }

    @Test("sends its headers")
    func headers() async throws {
        let stub = StubTransport { _, _ in .raw(200, "{}") }
        _ = await client(stub).value(["user"], as: [String: String].self)

        #expect(try #require(stub.requests.first).headers["Authorization"] == "Bearer t0ken")
    }

    @Test("joins segments below the base path, escaping a slash inside one")
    func segments() {
        let stub = StubTransport { _, _ in .raw(200) }
        let url = client(stub).url(
            ["projects", "acme/sub/api", "jobs"],
            [URLQueryItem(name: "scope[]", value: "running")]
        )

        #expect(url.path(percentEncoded: true) == "/api/v4/projects/acme%2Fsub%2Fapi/jobs")
        #expect(url.query(percentEncoded: false) == "scope[]=running")
    }

    @Test("follows Link headers to the last page")
    func pagination() async throws {
        let stub = StubTransport { request, _ in
            switch request.query("page") {
                case nil:
                    .raw(
                        200,
                        "[1, 2]",
                        headers: [
                            "Link":
                                #"<https://gitlab.example.com/api/v4/projects/acme%2Fapi/jobs?page=2>; rel="next""#
                        ]
                    )
                default: .raw(200, "[3]")
            }
        }
        let numbers = try await client(stub).all(
            ["projects", "acme/api", "jobs"],
            [.perPage],
            as: [Int].self
        ).get()

        #expect(numbers == [1, 2, 3])
        #expect(stub.encodedPaths.last == "/api/v4/projects/acme%2Fapi/jobs")
    }

    @Test("retries server errors, then succeeds")
    func retries() async throws {
        let stub = StubTransport { _, attempt in attempt < 2 ? .raw(502) : .raw(200, "[1]") }

        #expect(try await client(stub).value(["x"], as: [Int].self).get() == [1])
        #expect(stub.requests.count == 3)
    }

    @Test("gives up after the policy's retries")
    func exhausted() async {
        let stub = StubTransport { _, _ in .raw(503, #"{"message":"busy"}"#) }

        #expect(
            await client(stub).value(["x"], as: [Int].self)
                == .failure(.server(status: 503, message: "busy"))
        )
        #expect(stub.requests.count == 3)
    }

    @Test("does not retry a rejected token")
    func noRetry() async {
        let stub = StubTransport { _, _ in .raw(401, #"{"message":"Bad credentials"}"#) }

        #expect(
            await client(stub).value(["x"], as: [Int].self)
                == .failure(.unauthorized("Bad credentials"))
        )
        #expect(stub.requests.count == 1)
    }

    @Test("reads dates with and without fractional seconds")
    func dates() {
        #expect(
            JSONCoding.parseDate("2026-11-15T15:13:09Z")
                == Date(timeIntervalSince1970: 1_794_755_589)
        )
        #expect(
            JSONCoding.parseDate("2026-11-15T15:13:09.500Z")
                == Date(timeIntervalSince1970: 1_794_755_589.5)
        )
        #expect(JSONCoding.parseDate("yesterday") == nil)
    }
}
