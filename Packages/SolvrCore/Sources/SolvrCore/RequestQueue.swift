import Foundation

/// A concurrency limiter for outbound API calls.
///
/// The results screen fires five requests at once -- steps, formulas, lesson,
/// videos and a title -- and the API rate-limits well before the device runs out
/// of sockets. Four in flight is the compromise: the first tab is populated
/// quickly, and a burst does not earn a 429 for the whole screen.
///
/// A leaked slot is permanent and silent: lose four and the app never makes
/// another request, with no error to show for it. That is why the caller must
/// release in a `defer`, and why this type is here rather than in the app --
/// concurrency you cannot test is concurrency you are guessing about.
public actor RequestQueue {
    private var activeCount = 0
    private let maxConcurrent: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// Number of slots currently held. Exposed for tests, which is the only way
    /// to prove a slot came back.
    public var inFlight: Int { activeCount }

    public func acquire() async {
        if activeCount < maxConcurrent {
            activeCount += 1
        } else {
            // The slot is handed over directly on release, so the count is not
            // touched here -- incrementing would double-count it.
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    public func release() {
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            activeCount -= 1
        }
    }

    /// Run `body` holding a slot, releasing it on every exit path including a
    /// thrown error. Preferred over paired acquire/release calls: the pairing is
    /// what goes wrong.
    public func withSlot<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await body()
    }
}
