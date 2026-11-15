import FP
import Foundation
import Synchronization
import Testing

@testable import RunnersKit

@Suite("Watch history")
struct WatchHistoryTests {
    let app = Fixtures.repository("octo/app")

    func active(_ id: Int, branch: String = "main", minutesAgo: Double = 5) -> ActiveRun {
        let run = Fixtures.run(id, .running, minutesAgo: minutesAgo)
        return ActiveRun(repository: app, run: run.with(branch: branch))
    }

    func finished(_ active: ActiveRun, _ conclusion: Conclusion = .success) -> ActiveRun {
        ActiveRun(repository: active.repository, run: active.run.finished(conclusion))
    }

    func snapshot(_ runs: [ActiveRun]) -> StatusSnapshot {
        StatusSnapshot(
            provider: GitHubProvider(),
            owner: nil,
            repositoryCount: 1,
            runs: runs,
            rateLimit: nil,
            fetchedAt: Fixtures.now
        )
    }

    @Test("keeps a run that finished, with how it ended")
    func keepsFinished() {
        var history = WatchHistory()
        let run = active(7)
        _ = history.record(snapshot([run]), ended: [])
        #expect(history.ended(in: snapshot([])).map(\.id) == [run.id])
        let shown = history.record(snapshot([]), ended: [(run, .success(finished(run, .failure)))])
        #expect(shown.runs.map(\.run.conclusion) == [.failure])
        #expect(history.unfinished.isEmpty)
        // It stays on later snapshots without being read again.
        #expect(history.ended(in: snapshot([])).isEmpty)
        #expect(history.record(snapshot([]), ended: []).runs.map(\.id) == [run.id])
    }

    @Test("asks again about a run it could not read, and drops one that is gone")
    func unreadable() {
        var history = WatchHistory()
        let (kept, gone) = (active(7), active(8))
        _ = history.record(snapshot([kept, gone]), ended: [])
        let shown = history.record(
            snapshot([]),
            ended: [
                (kept, .failure(.server(status: 502, message: ""))),
                (gone, .failure(.notFound("run"))),
            ]
        )
        #expect(shown.runs.isEmpty)
        #expect(history.ended(in: snapshot([])).map(\.id) == [kept.id])
    }

    @Test("drops a run that left the statuses asked for without finishing")
    func leftStatuses() {
        var history = WatchHistory()
        let run = active(7)
        _ = history.record(snapshot([run]), ended: [])
        #expect(history.record(snapshot([]), ended: [(run, .success(run))]).runs.isEmpty)
        #expect(history.unfinished.isEmpty)
    }

    @Test("replaces a finished run with a newer run of the same workflow on the same branch")
    func replaced() {
        var history = WatchHistory()
        let (old, other) = (active(7, minutesAgo: 10), active(8, branch: "dev", minutesAgo: 10))
        _ = history.record(snapshot([old, other]), ended: [])
        _ = history.record(
            snapshot([]),
            ended: [(old, .success(finished(old))), (other, .success(finished(other)))]
        )
        let newer = active(9, minutesAgo: 1)
        #expect(
            history.record(snapshot([newer]), ended: []).runs.map(\.id) == [newer.id, other.id]
        )
    }

    @Test("shows a finished run again as active when it is re-run")
    func rerun() {
        var history = WatchHistory()
        let run = active(7)
        _ = history.record(snapshot([run]), ended: [])
        _ = history.record(snapshot([]), ended: [(run, .success(finished(run)))])
        let shown = history.record(snapshot([run]), ended: [])
        #expect(shown.runs.map(\.run.status) == [.running])
        #expect(history.finished.isEmpty)
    }

    @Test("reads a run once more when it drops out, and keeps it in the watch")
    func watch() async {
        let run = active(7)
        let service = EndingService(first: run, last: finished(run, .timedOut))
        var results: [Result<StatusSnapshot, RunnersError>] = []
        for await result in RunsMonitor(service: service).watch(StatusQuery(), every: .zero).prefix(
            3
        ) {
            results.append(result)
        }
        let statuses = results.map { (try? $0.get())?.runs.map(\.run.status) }
        #expect(statuses == [[.running], [.completed], [.completed]])
        #expect(service.latestReads == 1)
    }

    /// Reports `first` as active on the first look only, and `last` when asked how it ended.
    final class EndingService: CIService {
        let provider: any Provider = GitHubProvider()
        let first: ActiveRun
        let last: ActiveRun
        private let looks = Atomic(0)
        private let reads = Atomic(0)

        init(first: ActiveRun, last: ActiveRun) {
            self.first = first
            self.last = last
        }

        var latestReads: Int { reads.load(ordering: .relaxed) }

        func scope(for query: StatusQuery) async -> Result<MonitorScope, RunnersError> {
            .success(MonitorScope(owner: nil, repositories: [first.repository]))
        }

        func activeRuns(
            in repositories: [Repository],
            query: StatusQuery
        ) async -> Result<[ActiveRun], RunnersError> {
            .success(looks.add(1, ordering: .relaxed).newValue == 1 ? [first] : [])
        }

        func latest(_ run: ActiveRun, query: StatusQuery) async -> Result<ActiveRun, RunnersError> {
            reads.add(1, ordering: .relaxed)
            return .success(last)
        }

        func rateLimit() async -> RateLimit? { nil }
    }
}

extension Run {
    func with(branch: String) -> Run {
        Run(
            id: id,
            name: name,
            title: title,
            number: number,
            attempt: attempt,
            trigger: trigger,
            status: status,
            conclusion: conclusion,
            branch: branch,
            commit: commit,
            webURL: webURL,
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: completedAt,
            actor: actor
        )
    }

    func with(completedAt: Date?) -> Run {
        Run(
            id: id,
            name: name,
            title: title,
            number: number,
            attempt: attempt,
            trigger: trigger,
            status: status,
            conclusion: conclusion,
            branch: branch,
            commit: commit,
            webURL: webURL,
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: completedAt,
            actor: actor
        )
    }

    func finished(_ conclusion: Conclusion, minutesAgo: Double = 1) -> Run {
        Run(
            id: id,
            name: name,
            title: title,
            number: number,
            attempt: attempt,
            trigger: trigger,
            status: .completed,
            conclusion: conclusion,
            branch: branch,
            commit: commit,
            webURL: webURL,
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: Fixtures.minutesAgo(minutesAgo),
            actor: actor
        )
    }
}
