import FP
import Foundation
import RunnersKit

/// The API responses `runners` keeps between runs, in the user's caches folder, so a fresh run
/// asks with `If-None-Match` too and pays only for what changed.
struct ResponseCache: Sendable {
    let cache: ETagCache
    /// Where it is saved; nil when it is off or there is no caches folder.
    let file: URL?

    /// The saved cache, or an empty one when it is off, missing or unreadable: a cache is never
    /// a reason to fail.
    static func load(enabled: Bool, file: URL? = defaultFile) -> ResponseCache {
        guard enabled, let file else { return ResponseCache(cache: ETagCache(), file: nil) }
        return ResponseCache(
            cache: ETagCache.load(from: file).getOrElse(ETagCache()),
            file: file
        )
    }

    /// `~/Library/Caches/runners/responses.json` on macOS, `~/.cache/runners/responses.json`
    /// on Linux.
    static var defaultFile: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "runners/responses.json")
    }

    /// Best effort: a cache that cannot be saved costs requests next time, nothing more.
    func save() {
        guard let file else { return }
        _ = cache.save(to: file)
    }
}
