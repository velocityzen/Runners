import Foundation

/// An AWS region, such as `us-east-1`, with CodeBuild's endpoint and console pages in it.
public struct AWSRegion: Sendable, Hashable, CustomStringConvertible {
    public let name: String

    /// A region name: lowercase words and a number, joined by hyphens, such as `us-gov-west-1`.
    public init?(_ name: String) {
        let parts = name.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 3,
            parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(Self.isNameCharacter) }),
            parts.first?.allSatisfy(\.isLetter) == true,
            parts.last?.allSatisfy(\.isNumber) == true
        else { return nil }
        self.name = name
    }

    /// The region of a CodeBuild endpoint: `https://codebuild.us-east-1.amazonaws.com`, its
    /// FIPS one `codebuild-fips.…`, or China's `….amazonaws.com.cn`.
    public init?(codeBuildEndpoint url: URL) {
        let labels = (url.host() ?? "").split(separator: ".").map(String.init)
        guard labels.count >= 4,
            ["codebuild", "codebuild-fips"].contains(labels[0]),
            ["amazonaws.com", "amazonaws.com.cn"].contains(
                labels.dropFirst(2).joined(separator: ".")
            )
        else { return nil }
        self.init(labels[1])
    }

    public var description: String {
        name
    }

    /// `https://codebuild.us-east-1.amazonaws.com`
    public var codeBuildEndpoint: URL {
        URL(string: "https://codebuild.\(name).\(dnsSuffix)") ?? URL(filePath: "/")
    }

    var dnsSuffix: String {
        name.hasPrefix("cn-") ? "amazonaws.com.cn" : "amazonaws.com"
    }

    var consoleHost: String {
        if name.hasPrefix("cn-") { return "console.amazonaws.cn" }
        if name.hasPrefix("us-gov-") { return "console.amazonaws-us-gov.com" }
        return "\(name).console.aws.amazon.com"
    }

    // MARK: - Console pages

    /// A project's build history.
    func projectPage(_ project: String, account: String?) -> URL {
        consolePage(["projects", project, "history"], account: account)
    }

    func buildPage(_ buildID: String, project: String, account: String?) -> URL {
        consolePage(["projects", project, "build", buildID, ""], account: account)
    }

    /// `https://us-east-1.console.aws.amazon.com/codesuite/codebuild/<account>/projects/…`
    func consolePage(_ segments: [String], account: String?) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = consoleHost
        components.percentEncodedPath =
            "/"
            + (["codesuite", "codebuild"] + [account].compactMap { $0 } + segments)
            .map { $0.addingPercentEncoding(withAllowedCharacters: Self.consoleSegment) ?? $0 }
            .joined(separator: "/")
        components.queryItems = [URLQueryItem(name: "region", value: name)]
        return components.url ?? codeBuildEndpoint
    }

    static func isNameCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLowercase || character.isNumber)
    }

    /// What may stand unescaped in a console path segment. A build ID's `:` is escaped, as
    /// the console does.
    static let consoleSegment = CharacterSet.pathSegmentAllowed.subtracting(
        CharacterSet(charactersIn: ":")
    )
}

/// The parts of an Amazon Resource Name:
/// `arn:aws:codebuild:us-east-1:123456789012:project/name`.
enum AWSARN {
    /// The account ID, the fifth part.
    static func account(_ arn: String?) -> String? {
        part(4, of: arn)
    }

    /// The name after the resource type, without a version: `name` in `fleet/name:uuid`.
    static func resourceName(_ arn: String?) -> String? {
        part(5, of: arn)
            .flatMap { $0.split(separator: "/", maxSplits: 1).last }
            .flatMap { $0.split(separator: ":").first }
            .map(String.init)
    }

    static func part(_ index: Int, of arn: String?) -> String? {
        let parts = arn?.split(separator: ":", maxSplits: 5, omittingEmptySubsequences: false) ?? []
        guard parts.first == "arn", parts.count > index, !parts[index].isEmpty else { return nil }
        return String(parts[index])
    }
}
