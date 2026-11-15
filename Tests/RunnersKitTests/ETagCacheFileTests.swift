import FP
import Foundation
import Testing

@testable import RunnersKit

@Suite("Response cache on disk")
struct ETagCacheFileTests {
    let url = Fixtures.url("https://api.github.com/repos/octo/repo/actions/runs?status=queued")
    let other = Fixtures.url("https://api.github.com/repos/octo/web/actions/runs?status=queued")
    let file = FileManager.default.temporaryDirectory
        .appending(path: "runners-\(UUID().uuidString)/cache/responses.json")

    func entry(_ body: String, daysAgo: Double = 0) -> ETagCache.Entry {
        ETagCache.Entry(
            etag: "\"\(body)\"",
            response: HTTPResponse(status: 200, headers: ["Link": "<next>"], body: Data(body.utf8)),
            usedAt: Fixtures.now.addingTimeInterval(-daysAgo * 86_400)
        )
    }

    @Test("lets a later run ask with the ETag an earlier one saved, readable by the user only")
    func roundTrip() async throws {
        let earlier = ETagCache(now: { Fixtures.now })
        let first = StubTransport { _, _ in .raw(200, "runs", headers: ["ETag": "\"r1\""]) }
        _ = await ConditionalTransport(first, cache: earlier).send(HTTPRequest(url: url))
        try earlier.save(to: file).get()

        let later = try ETagCache.load(from: file).get()
        let second = StubTransport { _, _ in .raw(304) }
        let response = try await ConditionalTransport(second, cache: later)
            .send(HTTPRequest(url: url)).get()
        #expect(second.requests[0].headers["If-None-Match"] == "\"r1\"")
        #expect(response.body == Data("runs".utf8))

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    @Test("keeps what another run saved, the newer entry for a URL, and drops week-old ones")
    func merge() throws {
        let stale = Fixtures.url("https://api.github.com/repos/octo/old/actions/workflows")
        try ETagCache.write(
            [url: entry("theirs"), other: entry("theirs"), stale: entry("old", daysAgo: 8)],
            to: file
        ).get()
        let mine = ETagCache(
            entries: [url: entry("mine"), other: entry("mine", daysAgo: 1)],
            now: { Fixtures.now }
        )
        try mine.save(to: file).get()

        let saved = try ETagCache.entries(in: file).get()
        #expect(saved[url]?.etag == "\"mine\"")
        #expect(saved[other]?.etag == "\"theirs\"")
        #expect(saved[stale] == nil)
        #expect(saved[url]?.response.header("link") == "<next>")
    }

    @Test("starts empty without a file, and fails on one it cannot read")
    func unreadable() throws {
        #expect(try ETagCache.entries(in: file).get().isEmpty)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: file)
        #expect(!ETagCache.load(from: file).isSuccess)
    }
}
