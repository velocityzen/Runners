import FP
import Foundation

/// Namespace's GitHub runner services, served over Connect.
struct NamespaceAPI: Sendable {
    static let jobsService = "namespace.cloud.github.v1beta.JobsService"
    static let profileService = "namespace.cloud.github.v1beta.ProfileService"
    /// Added to the message when Namespace rejects the token.
    static let tokenHelp =
        "NSC_TOKEN takes a token from `nsc token create` that grants list and get on "
        + "github/runner-profile and instance, or run `nsc login` to use the CLI's"

    let connect: ConnectClient

    /// Namespace answers a token it can't read with `invalid_argument`, not
    /// `unauthenticated`.
    @Sendable
    static func rejectsToken(_ error: ConnectError) -> Bool {
        error.code == "unauthenticated"
            || (error.code == "invalid_argument"
                && error.message?.hasPrefix("invalid token") == true)
    }

    /// Every job the request matches, page after page.
    func jobs(_ request: NamespaceListJobs) async -> Result<[NamespaceJob], RunnersError> {
        await connect.all(Self.jobsService, "ListJobs", request, as: NamespaceJobsPage.self)
    }

    /// The latest jobs, finished or not: one page.
    func recentJobs() async -> Result<[NamespaceJob], RunnersError> {
        await connect.call(
            Self.jobsService,
            "ListJobs",
            NamespaceListJobs(),
            as: NamespaceJobsPage.self
        )
        .map(\.items)
    }

    /// One job, with the runner and instance it was given.
    func job(_ id: String) async -> Result<NamespaceJob, RunnersError> {
        await connect.call(
            Self.jobsService,
            "DescribeJob",
            ["jobId": id],
            as: NamespaceJobDescription.self
        )
        .flatMap { .fromOptional($0.job, error: .notFound("Namespace job \(id)")) }
    }

    /// The runner profiles' machines, by tag.
    func shapes() async -> Result<[String: NamespaceShape], RunnersError> {
        await connect.call(
            Self.profileService,
            "ListProfiles",
            [String: String](),
            as: NamespaceProfiles.self
        )
        .map(\.shapes)
    }
}
