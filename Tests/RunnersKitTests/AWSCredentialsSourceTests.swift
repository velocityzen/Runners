import Foundation
import Synchronization
import Testing

@testable import RunnersKit

@Suite("AWS credentials that expire")
struct AWSCredentialsSourceTests {
    let now = Fixtures.now

    func keys(_ id: String, expiringIn minutes: Double?) -> AWSCredentials {
        AWSCredentials(
            accessKeyID: id,
            secretAccessKey: "secret",
            sessionToken: "token",
            expiration: minutes.map { now.addingTimeInterval($0 * 60) }
        )
    }

    @Test("uses them as they are until five minutes before they expire, and always without a fetch")
    func asTheyAre() async throws {
        let fetches = Atomic(0)
        let source = AWSCredentialsSource(keys("OLD", expiringIn: 5.1)) {
            fetches.add(1, ordering: .relaxed)
            return .success(keys("NEW", expiringIn: 60))
        }
        #expect(try await source.current(at: now).get().accessKeyID == "OLD")
        #expect(fetches.load(ordering: .relaxed) == 0)

        let expired = AWSCredentialsSource(keys("SET", expiringIn: -1))
        #expect(try await expired.current(at: now).get().accessKeyID == "SET")
    }

    @Test("fetches new ones within five minutes of expiry, once for calls made together")
    func shared() async throws {
        let fetches = Atomic(0)
        let source = AWSCredentialsSource(keys("OLD", expiringIn: 4)) {
            fetches.add(1, ordering: .relaxed)
            try? await Task.sleep(for: .milliseconds(50))
            return .success(keys("NEW", expiringIn: 60))
        }
        let now = now
        let ids = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<8 {
                group.addTask { try? await source.current(at: now).get().accessKeyID }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(ids == Array(repeating: "NEW", count: 8))
        #expect(fetches.load(ordering: .relaxed) == 1)
        #expect(try await source.current(at: now + 60).get().accessKeyID == "NEW")
        #expect(fetches.load(ordering: .relaxed) == 1)
    }

    @Test("keeps the old ones while fetches fail, fetching every 30 seconds, then fails")
    func failing() async throws {
        let fetches = Atomic(0)
        let fails = Atomic(true)
        let signIn = RunnersError.tokenUnavailable("run `aws sso login`")
        let source = AWSCredentialsSource(keys("OLD", expiringIn: 2)) {
            fetches.add(1, ordering: .relaxed)
            guard !fails.load(ordering: .relaxed) else { return .failure(signIn) }
            return .success(keys("NEW", expiringIn: 60))
        }
        #expect(try await source.current(at: now).get().accessKeyID == "OLD")
        #expect(try await source.current(at: now + 10).get().accessKeyID == "OLD")
        #expect(fetches.load(ordering: .relaxed) == 1)

        // Expired, and 30 seconds since the last fetch: fetches again, and fails with it.
        #expect(await source.current(at: now + 150).error == signIn)
        #expect(fetches.load(ordering: .relaxed) == 2)
        // Within 30 seconds of that one: the same failure, without a fetch.
        #expect(await source.current(at: now + 170).error == signIn)
        #expect(fetches.load(ordering: .relaxed) == 2)

        // Signed in again: the next fetch takes.
        fails.store(false, ordering: .relaxed)
        #expect(try await source.current(at: now + 180).get().accessKeyID == "NEW")
        #expect(fetches.load(ordering: .relaxed) == 3)
    }
}
