import FPRetry
import Foundation
import Testing

@testable import RunnersKit

@Suite("GitHub client")
struct GitHubClientTests {
    func client(_ stub: StubTransport) -> GitHubClient {
        GitHubClient(token: "t0ken", transport: stub, retryPolicy: .limitRetries(2))
    }

    @Test("sends the token, API version and a user agent")
    func headers() async throws {
        let stub = StubTransport { _, _ in .json(Fixtures.me) }
        _ = try await client(stub).authenticatedUser().get()

        let headers = try #require(stub.requests.first).headers
        #expect(headers["Authorization"] == "Bearer t0ken")
        #expect(headers["X-GitHub-Api-Version"] == GitHubClient.apiVersion)
        #expect(headers["User-Agent"] != nil)
        #expect(stub.paths == ["/user"])
    }

    @Test("follows Link headers to the last page")
    func pagination() async throws {
        let repos = (1...3).map { (n: Int) in Fixtures.repository("r\(n)", id: n) }
        let stub = StubTransport { request, _ in
            switch request.query("page") {
                case nil:
                    .json([repos[0], repos[1]], headers: ["Link": #"<https://api.github.com/user/repos?page=2>; rel="next""#])
                default:
                    .json([repos[2]])
            }
        }
        let listed = try await client(stub).repositories(.authenticatedUser).get()

        #expect(listed.map(\.name) == ["r1", "r2", "r3"])
        #expect(stub.requests.first?.query("affiliation") == "owner")
        #expect(stub.requests.first?.query("per_page") == "100")
    }

    @Test("retries server errors, then succeeds")
    func retries() async throws {
        let stub = StubTransport { _, attempt in attempt < 2 ? .raw(502) : .json(Fixtures.me) }
        let user = try await client(stub).authenticatedUser().get()

        #expect(user == Fixtures.me)
        #expect(stub.requests.count == 3)
    }

    @Test("gives up after the policy's retries")
    func exhausted() async {
        let stub = StubTransport { _, _ in .raw(503, #"{"message":"busy"}"#) }
        let result = await client(stub).authenticatedUser()

        #expect(result == .failure(.server(status: 503, message: "busy")))
        #expect(stub.requests.count == 3)
    }

    @Test("does not retry a rejected token")
    func noRetry() async {
        let stub = StubTransport { _, _ in .raw(401, #"{"message":"Bad credentials"}"#) }
        let result = await client(stub).authenticatedUser()

        #expect(result == .failure(.unauthorized("Bad credentials")))
        #expect(stub.requests.count == 1)
    }

    @Test("picks the listing that sees the most repositories")
    func listings() {
        let other = Account(id: 3, login: "hubot", kind: .user)
        let meShouting = Account(id: 1, login: "OCTO", kind: .user)

        #expect(RepositoryListing.of(Fixtures.org, viewer: Fixtures.me) == .organization("acme"))
        #expect(RepositoryListing.of(meShouting, viewer: Fixtures.me) == .authenticatedUser)
        #expect(RepositoryListing.of(other, viewer: Fixtures.me) == .user("hubot"))
    }

    @Test("maps API URLs to gh hostnames")
    func hostnames() {
        #expect(GHCLI.hostname(forAPI: GitHubClient.defaultBaseURL) == nil)
        #expect(GHCLI.hostname(forAPI: Fixtures.url("https://ghe.example.com/api/v3")) == "ghe.example.com")
        #expect(GHCLI.hostname(forAPI: Fixtures.url("https://api.acme.ghe.com")) == "acme.ghe.com")
    }
}
