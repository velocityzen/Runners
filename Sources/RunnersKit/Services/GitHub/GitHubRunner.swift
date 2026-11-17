import Foundation

/// A self-hosted runner, from `GET /orgs/{org}/actions/runners` or
/// `GET /repos/{owner}/{repo}/actions/runners`.
struct GitHubRunner: Codable, Sendable, Hashable {
    struct Label: Codable, Sendable, Hashable {
        let name: String
    }

    let id: Int
    let name: String
    let os: String?
    /// `online` or `offline`.
    let status: String
    let busy: Bool
    let ephemeral: Bool?
    let labels: [Label]

    var runner: Runner {
        Runner(
            id: String(id),
            name: name,
            kind: .selfHosted,
            status: Runner.Status(rawValue: status) ?? .unknown,
            busy: busy,
            ephemeral: ephemeral ?? false,
            labels: labels.map(\.name),
            details: os
        )
    }
}

struct GitHubRunnersPage: PagedResponse, Codable {
    let totalCount: Int
    let runners: [GitHubRunner]

    var items: [GitHubRunner] { runners }

    enum CodingKeys: String, CodingKey {
        case runners
        case totalCount = "total_count"
    }
}

/// A pool of larger runners GitHub runs for an organization, from
/// `GET /orgs/{org}/actions/hosted-runners`. Jobs ask for it by name.
struct GitHubHostedRunner: Codable, Sendable, Hashable {
    struct Image: Codable, Sendable, Hashable {
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    struct MachineSize: Codable, Sendable, Hashable {
        /// `4-core`
        let id: String
    }

    let id: Int
    let name: String
    /// `linux-x64`
    let platform: String?
    /// `Ready`, `Provisioning`, `Shutdown`, `Deleting` or `Stuck`.
    let status: String
    let maximumRunners: Int?
    let imageDetails: Image?
    let machineSizeDetails: MachineSize?

    enum CodingKeys: String, CodingKey {
        case id, name, platform, status
        case maximumRunners = "maximum_runners"
        case imageDetails = "image_details"
        case machineSizeDetails = "machine_size_details"
    }

    var runner: Runner {
        Runner(
            id: "hosted-\(id)",
            name: name,
            kind: .githubHosted,
            status: runnerStatus,
            busy: nil,
            details: [
                platform,
                machineSizeDetails?.id,
                imageDetails?.displayName,
                maximumRunners.map { "up to \($0)" },
            ]
            .compactMap(\.self)
            .joined(separator: ", ")
        )
    }

    var runnerStatus: Runner.Status {
        switch status.lowercased() {
            case "ready": .online
            case "provisioning": .provisioning
            case "shutdown", "deleting", "stuck": .offline
            default: .unknown
        }
    }
}

struct GitHubHostedRunnersPage: PagedResponse, Codable {
    let totalCount: Int
    let runners: [GitHubHostedRunner]

    var items: [GitHubHostedRunner] { runners }

    enum CodingKeys: String, CodingKey {
        case runners
        case totalCount = "total_count"
    }
}
