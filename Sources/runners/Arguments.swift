import ArgumentParser
import RunnersKit

extension Provider: ExpressibleByArgument {
    public var defaultValueDescription: String {
        rawValue
    }
}

extension RunStatus: ExpressibleByArgument {
    public init?(argument: String) {
        guard let status = RunStatus(rawValue: argument), RunStatus.active.contains(status) else {
            return nil
        }
        self = status
    }

    public static var allValueStrings: [String] {
        active.map(\.rawValue)
    }

    public var defaultValueDescription: String {
        rawValue
    }
}
