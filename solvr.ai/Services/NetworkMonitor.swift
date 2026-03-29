import Network
import Foundation

@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private(set) var isConnected = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "ai.solvr.networkmonitor"))
    }

    deinit {
        monitor.cancel()
    }
}
