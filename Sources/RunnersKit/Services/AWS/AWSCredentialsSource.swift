import Foundation

/// The credentials to sign with, fetched again shortly before they expire, so a watch outlives
/// temporary keys such as SSO's or a role's.
///
/// Calls made while a fetch is under way share it. A fetch that fails leaves the current
/// credentials in use while they work, and is tried again at most every ``retryDelay``; once
/// they have expired, the failure is the answer, until a fetch succeeds.
actor AWSCredentialsSource {
    /// How long before credentials expire that new ones are fetched: time enough for a call
    /// signed with them to be answered, and for a clock that runs slow.
    static let margin: TimeInterval = 5 * 60

    /// The least time between fetches.
    static let retryDelay: TimeInterval = 30

    typealias Fetch = @Sendable () async -> Result<AWSCredentials, RunnersError>

    private var credentials: AWSCredentials
    /// Fetches new credentials; nil for ones that are used as they are.
    nonisolated let refresh: Fetch?
    private var fetching: Task<Result<AWSCredentials, RunnersError>, Never>?
    private var lastFetch: Date?
    private var failure: RunnersError?

    init(_ credentials: AWSCredentials, refresh: Fetch? = nil) {
        self.credentials = credentials
        self.refresh = refresh
    }

    /// The credentials to sign a request sent at `now` with.
    func current(at now: Date) async -> Result<AWSCredentials, RunnersError> {
        guard let refresh, credentials.expire(within: Self.margin, of: now) else {
            return .success(credentials)
        }
        if let fetching {
            return await settle(fetching, at: now)
        }
        if let lastFetch, now.timeIntervalSince(lastFetch) < Self.retryDelay {
            return usable(at: now)
        }
        lastFetch = now
        let fetch = Task { await refresh() }
        fetching = fetch
        return await settle(fetch, at: now)
    }

    /// Waits for `fetch`. Whichever caller resumes first keeps what it got.
    private func settle(
        _ fetch: Task<Result<AWSCredentials, RunnersError>, Never>,
        at now: Date
    ) async -> Result<AWSCredentials, RunnersError> {
        let result = await fetch.value
        if fetching == fetch {
            fetching = nil
            switch result {
                case .success(let fresh):
                    credentials = fresh
                    failure = nil
                case .failure(let error):
                    failure = error
            }
        }
        return usable(at: now)
    }

    /// The current credentials, unless they have expired and the last fetch failed.
    private func usable(at now: Date) -> Result<AWSCredentials, RunnersError> {
        if let failure, credentials.expire(within: 0, of: now) {
            return .failure(failure)
        }
        return .success(credentials)
    }
}
