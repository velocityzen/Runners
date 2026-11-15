import ArgumentParser
import RunnersKit

extension ActionStatus: ExpressibleByArgument {
    public init?(argument: String) {
        guard let status = ActionStatus(rawValue: argument), ActionStatus.queryable.contains(status) else {
            return nil
        }
        self = status
    }

    public static var allValueStrings: [String] {
        queryable.map(\.rawValue)
    }

    public var defaultValueDescription: String {
        rawValue
    }
}
