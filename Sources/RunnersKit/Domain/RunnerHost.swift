import Foundation

/// Who runs the machine a job asks for, when that isn't the CI service itself: the runner
/// vendors whose machines register with GitHub as self-hosted runners, told apart by the
/// labels their runners answer to. Blacksmith and Ubicloud have no API of their own for
/// runner status, so their labels are the only way to tell.
public enum RunnerHost: String, Codable, Sendable, CaseIterable {
    case depot
    case blacksmith
    case warpBuild = "warpbuild"
    case namespace
    case ubicloud
    case codeBuild = "codebuild"

    /// `Depot`
    public var name: String {
        switch self {
            case .depot: "Depot"
            case .blacksmith: "Blacksmith"
            case .warpBuild: "WarpBuild"
            case .namespace: "Namespace"
            case .ubicloud: "Ubicloud"
            case .codeBuild: "AWS CodeBuild"
        }
    }

    /// What its labels start with: `depot-ubuntu-24.04`, `ubicloud` and `ubicloud-standard-4`.
    public var labelPrefix: String {
        switch self {
            case .depot: "depot-"
            case .blacksmith: "blacksmith-"
            case .warpBuild: "warp-"
            case .namespace: "namespace-profile-"
            case .ubicloud: "ubicloud"
            case .codeBuild: "codebuild-"
        }
    }

    /// The host the label is one of, if any.
    public init?(label: String) {
        let label = label.lowercased()
        guard let host = Self.allCases.first(where: { label.hasPrefix($0.labelPrefix) }) else {
            return nil
        }
        self = host
    }

    /// The host of the first label that names one.
    public init?(labels: [String]) {
        guard let host = labels.lazy.compactMap(RunnerHost.init(label:)).first else {
            return nil
        }
        self = host
    }
}
