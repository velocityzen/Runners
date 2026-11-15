import FP
import Foundation

/// The cache kept in a file between runs, so a fresh process gets `304 Not Modified` too.
///
/// The file holds response bodies, so it is written readable by the user only. Several
/// processes can share it: each save merges with what is there, keeping the newer entry for a
/// URL, and drops entries no run has used for a week.
extension ETagCache {
    /// How long an entry nobody uses stays in the file.
    static let maxAge: TimeInterval = 7 * 86_400

    /// What the file looks like on disk.
    struct Stored: Codable {
        static let currentVersion = 1

        let version: Int
        let entries: [String: Entry]
    }

    /// The cache saved in `file`: empty when there is none yet, a failure when it cannot be
    /// read.
    public static func load(
        from file: URL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> Result<ETagCache, RunnersError> {
        entries(in: file).map { ETagCache(entries: $0, now: now) }
    }

    /// Writes the entries used in the last week, merged with the ones saved since this cache
    /// was loaded.
    public func save(to file: URL) -> Result<Void, RunnersError> {
        let saved = Self.entries(in: file).getOrElse([:])
        let merged = saved.merging(all) { old, new in new.usedAt >= old.usedAt ? new : old }
        let kept = Self.kept(merged, at: now())
        return Self.write(kept, to: file)
    }

    /// The entries in `file`; none when there is no file, or one from another version.
    static func entries(in file: URL) -> Result<[URL: Entry], RunnersError> {
        guard FileManager.default.fileExists(atPath: file.path) else { return .success([:]) }

        return Result { try JSONDecoder().decode(Stored.self, from: Data(contentsOf: file)) }
            .mapError { .cache("\(file.path) is not a response cache: \($0.localizedDescription)") }
            .map { stored in
                guard stored.version == Stored.currentVersion else { return [:] }
                return Dictionary(
                    stored.entries.compactMap { key, entry in URL(string: key).map { ($0, entry) }
                    },
                    uniquingKeysWith: { first, _ in first }
                )
            }
    }

    /// Entries used within ``maxAge``, at most ``capacity`` of them, the most recently used.
    static func kept(_ entries: [URL: Entry], at now: Date) -> [URL: Entry] {
        let recent = entries.filter { now.timeIntervalSince($0.value.usedAt) <= maxAge }
            .sorted { $0.value.usedAt > $1.value.usedAt }
            .prefix(capacity)
        return Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0.value) })
    }

    static func write(_ entries: [URL: Entry], to file: URL) -> Result<Void, RunnersError> {
        let stored = Stored(
            version: Stored.currentVersion,
            entries: Dictionary(
                uniqueKeysWithValues: entries.map { ($0.key.absoluteString, $0.value) }
            )
        )
        let files = FileManager.default
        return Result {
            try files.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try JSONEncoder().encode(stored).write(to: file, options: .atomic)
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        .mapError { .cache("could not write \(file.path): \($0.localizedDescription)") }
    }
}
