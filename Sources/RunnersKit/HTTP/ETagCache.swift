import Foundation
import Synchronization

/// Responses by URL, with the ETag the server sent for each and when each was last used.
public final class ETagCache: Sendable {
    struct Entry: Sendable, Equatable, Codable {
        let etag: String
        let response: HTTPResponse
        let usedAt: Date

        func used(at date: Date) -> Entry {
            Entry(etag: etag, response: response, usedAt: date)
        }
    }

    /// Enough for every repository and run of a large organization; cleared when exceeded.
    static let capacity = 4_096

    let now: @Sendable () -> Date
    private let entries: Mutex<[URL: Entry]>

    public convenience init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(entries: [:], now: now)
    }

    init(entries: [URL: Entry], now: @escaping @Sendable () -> Date) {
        self.entries = Mutex(entries)
        self.now = now
    }

    subscript(url: URL) -> Entry? {
        entries.withLock { $0[url] }
    }

    var all: [URL: Entry] {
        entries.withLock { $0 }
    }

    /// How many responses it holds.
    public var count: Int {
        entries.withLock { $0.count }
    }

    /// Swaps a 304 for the cached response, and caches a fresh response that has an ETag.
    func resolve(_ response: HTTPResponse, for url: URL, cached: Entry?) -> HTTPResponse {
        if response.status == 304, let cached {
            store(cached.used(at: now()), for: url)
            return cached.response.refreshed(with: response.headers)
        }
        if response.isSuccess, let etag = response.header("etag") {
            store(Entry(etag: etag, response: response, usedAt: now()), for: url)
        }
        return response
    }

    private func store(_ entry: Entry, for url: URL) {
        entries.withLock { entries in
            if entries[url] == nil, entries.count >= Self.capacity { entries.removeAll() }
            entries[url] = entry
        }
    }
}

extension HTTPResponse: Codable {
    enum CodingKeys: String, CodingKey {
        case status, headers, body
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            status: try container.decode(Int.self, forKey: .status),
            headers: try container.decode([String: String].self, forKey: .headers),
            body: try container.decode(Data.self, forKey: .body)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(headers, forKey: .headers)
        try container.encode(body, forKey: .body)
    }
}
