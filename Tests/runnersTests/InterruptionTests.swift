import Testing

@testable import runners

@Suite("Interruption")
struct InterruptionTests {
    @Test("lets the work finish when no signal comes")
    func finished() async {
        let (signals, _) = AsyncStream<Int32>.makeStream()
        let ending = await Interruption.race(
            { .finished(.failure(.unauthorized("bad token"))) },
            until: signals
        )
        guard case .finished(.failure(.unauthorized("bad token"))) = ending else {
            Issue.record("expected the work's failure, got \(ending)")
            return
        }
    }

    @Test("stops the work on a signal, and waits for it to clean up")
    func interrupted() async {
        let (signals, continuation) = AsyncStream<Int32>.makeStream()
        let cleanedUp = CleanUp()
        continuation.yield(2)
        let ending = await Interruption.race(
            {
                try? await Task.sleep(for: .seconds(3600))
                cleanedUp.mark()
                return .finished(.success(()))
            },
            until: signals
        )
        guard case .interrupted(signal: 2) = ending else {
            Issue.record("expected an interruption, got \(ending)")
            return
        }
        #expect(cleanedUp.isMarked)
    }

    @Test("ignores a signal stream that ends without a signal")
    func noSignals() async {
        let (signals, continuation) = AsyncStream<Int32>.makeStream()
        continuation.finish()
        let ending = await Interruption.race(
            {
                try? await Task.sleep(for: .milliseconds(20))
                return .finished(.success(()))
            },
            until: signals
        )
        guard case .finished(.success) = ending else {
            Issue.record("expected the work to finish, got \(ending)")
            return
        }
    }
}

import Synchronization

final class CleanUp: Sendable {
    private let marked = Atomic(false)

    func mark() {
        marked.store(true, ordering: .relaxed)
    }

    var isMarked: Bool {
        marked.load(ordering: .relaxed)
    }
}
