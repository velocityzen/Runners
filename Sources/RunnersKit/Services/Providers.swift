/// The providers this library comes with.
public enum Providers {
    /// GitHub, then GitLab. The first is the default.
    public static let builtIn: [any Provider] = [GitHubProvider(), GitLabProvider()]
}
