import Network
import Foundation
import os

/// Whether the device currently has a usable network path.
///
/// Deliberately **not** `@Observable`, and deliberately not main-actor isolated.
/// This target compiles with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an
/// ordinary type here is main-actor bound -- and the only thing that reads this
/// flag is an `AnthropicProvider.isOnline` closure, which is `@Sendable` and runs
/// on whatever context the request happens to be on. A main-actor property read
/// from there is a data race that the Swift 5 language mode reports as a warning
/// rather than an error, which is a bad reason to leave it in.
///
/// So the flag lives behind a lock and the type is `nonisolated`: correct to read
/// from any isolation, and no `@Observable` machinery for an observer that does
/// not exist. If the UI ever needs to show connectivity, add a main-actor
/// `@Observable` mirror that this feeds -- do not make this one racy to save a
/// type.
///
/// `OSAllocatedUnfairLock` rather than `Mutex` because the path-update handler
/// has to capture the storage, and `Mutex` is non-copyable.
nonisolated final class NetworkMonitor: Sendable {
    static let shared = NetworkMonitor()

    /// Starts optimistic. The first path update arrives quickly, and refusing to
    /// make a request before it lands would fail solves for no reason.
    private let connected = OSAllocatedUnfairLock(initialState: true)
    private let monitor = NWPathMonitor()

    var isConnected: Bool {
        connected.withLock { $0 }
    }

    private init() {
        monitor.pathUpdateHandler = { [connected] path in
            let satisfied = path.status == .satisfied
            connected.withLock { $0 = satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "ai.solvr.networkmonitor"))
    }

    deinit {
        monitor.cancel()
    }
}
