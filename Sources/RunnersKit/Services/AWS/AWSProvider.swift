import Foundation

/// AWS CodeBuild-hosted GitHub Actions runners, in one region. The AWS CLI supplies the
/// credentials and the region when none are set.
public struct AWSProvider: Provider {
    public let id = "aws"
    public let name = "AWS CodeBuild"
    /// The access key ID, its secret, and the session token of temporary keys, under the names
    /// the AWS CLI and SDKs read.
    public let tokenSettings: [ProviderSetting] = [
        .setting("aws.access_key_id"), .setting("aws.secret_access_key"),
        .setting("aws.session_token"),
    ]
    /// The region: `AWS_REGION` first, as the SDKs read it.
    public let apiURLSettings: [ProviderSetting] = [
        .setting("aws.region"), .environment("aws.default_region"),
    ]

    public init() {}

    public var repositoryTerm: (singular: String, plural: String) {
        ("project", "projects")
    }

    /// The key pair as credentials, or nil when neither half is set. One half alone is a
    /// mistake, not a reason to ask the AWS CLI.
    public func token(from value: ([ProviderSetting]) -> String?) -> Result<String?, RunnersError> {
        let (key, secret, session) = (
            value([tokenSettings[0]]), value([tokenSettings[1]]), value([tokenSettings[2]])
        )
        switch (key, secret) {
            case (nil, nil):
                return .success(nil)
            case (let key?, let secret?):
                return .success(
                    AWSCredentials(accessKeyID: key, secretAccessKey: secret, sessionToken: session)
                        .token
                )
            default:
                return .failure(
                    .configuration(
                        "set both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, or neither"
                    )
                )
        }
    }

    /// A region's CodeBuild endpoint.
    public func apiURL(_ value: String, from setting: ProviderSetting) -> URL? {
        AWSRegion(value)?.codeBuildEndpoint
    }

    public func apiURLFormat(of setting: ProviderSetting) -> String {
        "a region, such as us-east-1"
    }

    /// The AWS CLI's region, for its current profile.
    public func fallbackAPIURL() async -> Result<URL, RunnersError> {
        await AWSCLI.region.value { .configuration("no AWS region: \($0)") }
            .flatMap { printed in
                .fromOptional(
                    AWSRegion(printed)?.codeBuildEndpoint,
                    error: .configuration(
                        "\(AWSCLI.region.commandLine) printed \"\(printed)\", not a region; "
                            + "set AWS_REGION"
                    )
                )
            }
    }

    /// The AWS CLI's credentials, for its current profile: keys, SSO or a role.
    public func fallbackToken(apiURL: URL) async -> Result<String, RunnersError> {
        await AWSCLI.fetchCredentials().map(\.token)
    }

    public func isRepositoryName(_ name: String) -> Bool {
        CodeBuildProject.isName(name)
    }

    public var repositoryNameFormat: String {
        "a CodeBuild project name"
    }

    /// Credentials that expire came from the AWS CLI, the one source that says when they do,
    /// so it is asked for new ones before then. Ones that last are used as they are.
    public func service(token: String, apiURL: URL, transport: any HTTPTransport) -> any CIService {
        let credentials = AWSCredentials.from(token: token)
        let expires = credentials.map { $0.expiration != nil }.getOrElse(false)
        return AWSService(
            credentials: credentials,
            refresh: expires ? AWSCLI.fetchCredentials : nil,
            endpoint: apiURL,
            transport: transport
        )
    }
}

/// What `runners` asks the AWS CLI for, with the profile in `AWS_PROFILE`.
enum AWSCLI {
    static let credentials = CLIToken(
        "aws",
        ["configure", "export-credentials", "--format", "process"],
        hint: "set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, or sign in with `aws configure` "
            + "or `aws sso login`"
    )

    static let region = CLIToken(
        "aws",
        ["configure", "get", "region"],
        hint: "set AWS_REGION, or run `aws configure`"
    )

    /// The credentials ``credentials`` prints, with when they expire.
    static func fetchCredentials() async -> Result<AWSCredentials, RunnersError> {
        await credentials.token()
            .flatMap { printed in
                AWSCredentials.from(token: printed)
                    .mapError { _ in
                        .tokenUnavailable(
                            "\(credentials.commandLine) printed no credentials; "
                                + credentials.hint
                        )
                    }
            }
    }
}
