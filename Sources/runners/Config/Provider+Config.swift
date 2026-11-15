import FP
import Foundation
import RunnersKit

/// How any provider's settings are read: its token and API URL from the settings it names.
extension Provider {
    func token(in config: Config) -> String? {
        config.text(tokenSettings.map(SettingKey.init), isSecret: true)?.value
    }

    /// The URL given on the command line, else the first configured one, else the public
    /// service's.
    func apiURL(_ given: String?, in config: Config) -> Result<URL, RunnersError> {
        if let given { return Settings.url(given) }
        guard let (key, value) = config.text(apiURLSettings.map(SettingKey.init)),
            let setting = apiURLSettings.first(where: { SettingKey($0) == key })
        else {
            return .success(defaultAPIURL)
        }
        return .fromOptional(
            apiURL(value, from: setting),
            error: key.invalid(value, expected: "a URL")
        )
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

    /// `github or gitlab`
    var idList: String {
        map(\.id).formatted(.list(type: .or))
    }
}
