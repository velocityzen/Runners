extension DepotCIService {
    /// Depot CI has no list of repositories, so an organization's are those its latest runs,
    /// finished or not, were for, and an owner's are those named `owner/…`. A repository
    /// whose runs are older than that shows once it runs again, at the next read of the
    /// scope. `--repo` names repositories as they are.
    public func scope(for query: StatusQuery) async -> Result<MonitorScope, RunnersError> {
        switch query.target {
            case .authenticatedUser:
                await api.recentRuns()
                    .map { MonitorScope(owner: nil, repositories: Self.repositories(of: $0)) }

            case .owner(let name):
                await api.recentRuns()
                    .map { runs in
                        MonitorScope(
                            owner: Owner(id: name, login: name, kind: .unknown),
                            repositories: Self.repositories(of: runs)
                                .filter { Self.owner(of: $0.fullName) == name.lowercased() }
                        )
                    }

            case .repositories(let names):
                .success(MonitorScope(owner: nil, repositories: names.map(Repository.init(depot:))))
        }
    }

    /// The repositories of these runs, once each, in the order they come.
    static func repositories(of runs: [DepotRun]) -> [Repository] {
        runs.compactMap(\.repo)
            .filter { !$0.isEmpty }
            .uniqued { $0.lowercased() }
            .map(Repository.init(depot:))
    }

    static func owner(of fullName: String) -> String {
        String(fullName.split(separator: "/").first ?? "").lowercased()
    }
}
