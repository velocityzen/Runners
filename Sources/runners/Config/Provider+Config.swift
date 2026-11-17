import FP
import Foundation
import RunnersKit

/// How any provider's settings are read: its token and API URL from the settings it names.
extension Provider {
    /// The configured token, or nil to leave it to the provider's fallback.
    func token(in config: Config) -> Result<String?, RunnersError> {
        token { settings in config.text(settings.map(SettingKey.init), isSecret: true)?.value }
    }

    /// The URL given on the command line, else the first configured one, else nil to leave it
    /// to the provider's fallback.
    func apiURL(_ given: String?, in config: Config) -> Result<URL?, RunnersError> {
        if let given { return Settings.url(given).map(Optional.some) }
        guard let (key, value) = config.text(apiURLSettings.map(SettingKey.init)),
            let setting = apiURLSettings.first(where: { SettingKey($0) == key })
        else {
            return .success(nil)
        }
        let url = Result<URL, RunnersError>.fromOptional(
            apiURL(value, from: setting),
            error: key.invalid(value, expected: apiURLFormat(of: setting))
        )
        return url.map(Optional.some)
    }
}

extension Array where Element == any Provider {
    /// The provider given on the command line, else the configured one, else the first.
    func choice(_ given: String?, in config: Config) -> Result<any Provider, RunnersError> {
        guard let fallback = first else {
            return .failure(.configuration("there are no CI providers to choose from"))
        }
        guard let id = given ?? config.text(.provider) else { return .success(fallback) }
        return .fromOptional(
            named(id),
            error: SettingKey.provider.invalid(id, expected: idList)
        )
    }

    func named(_ id: String) -> (any Provider)? {
        first { $0.id == id.lowercased() }
    }

    /// `github, gitlab or aws`
    var idList: String {
        map(\.id).formatted(.list(type: .or))
    }
}
