/// The providers this library comes with.
public enum Providers {
    /// GitHub, GitLab, Forgejo Actions, Woodpecker CI, Depot CI, the runners of Depot,
    /// Namespace and WarpBuild, then AWS CodeBuild. The first is the default.
    public static let builtIn: [any Provider] = [
        GitHubProvider(), GitLabProvider(), ForgejoProvider(), WoodpeckerProvider(),
        DepotCIProvider(), DepotProvider(), NamespaceProvider(), WarpBuildProvider(),
        AWSProvider(),
    ]
}
