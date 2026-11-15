import RunnersKit

/// Every setting `runners` takes: its own, then each provider's.
struct SettingKeys: Sendable {
    /// What a `.runners` file may set.
    let inFiles: [SettingKey]
    /// The settings that hold a token, whose values stay out of logs.
    let secret: Set<SettingKey>

    init(providers: [any Provider]) {
        let own = providers.flatMap { ($0.tokenSettings + $0.apiURLSettings).filter(\.inFiles) }
        inFiles = (SettingKey.common + own.map(SettingKey.init)).uniqued()
        secret = Set(providers.flatMap { $0.tokenSettings.map(SettingKey.init) })
    }

    /// The key a `.runners` file spells this way.
    func key(fileName: String) -> SettingKey? {
        inFiles.first { $0.fileName == fileName }
    }
}

extension Array where Element: Hashable {
    /// The elements in order, each once.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
