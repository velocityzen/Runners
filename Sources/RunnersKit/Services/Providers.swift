/// The providers this library comes with.
public enum Providers {
    /// GitHub, GitLab, Forgejo Actions, then AWS CodeBuild. The first is the default.
    public static let builtIn: [any Provider] = [
        GitHubProvider(), GitLabProvider(), ForgejoProvider(), AWSProvider(),
    ]
}
