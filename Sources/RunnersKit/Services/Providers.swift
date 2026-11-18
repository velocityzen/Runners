/// The providers this library comes with.
public enum Providers {
    /// GitHub, GitLab, Forgejo Actions, Woodpecker CI, Depot CI, Depot's and Namespace's
    /// runners, then AWS CodeBuild. The first is the default.
    public static let builtIn: [any Provider] = [
        GitHubProvider(), GitLabProvider(), ForgejoProvider(), WoodpeckerProvider(),
        DepotCIProvider(), DepotProvider(), NamespaceProvider(), AWSProvider(),
    ]
}
