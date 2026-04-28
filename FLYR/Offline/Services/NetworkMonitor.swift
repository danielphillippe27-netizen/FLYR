import Foundation
import Network
import Combine

final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline = true
    @Published private(set) var connectionDescription = "Online"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.flyr.network-monitor", qos: .utility)
    private var hasStarted = false

    private init() {
        startIfNeeded()
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.apply(path: path)
            }
        }
        monitor.start(queue: queue)
    }

    private func apply(path: NWPath) {
        isOnline = path.status == .satisfied
        if path.status != .satisfied {
            connectionDescription = "Offline"
        } else if path.usesInterfaceType(.wifi) {
            connectionDescription = "Wi-Fi"
        } else if path.usesInterfaceType(.cellular) {
            connectionDescription = "Cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionDescription = "Ethernet"
        } else {
            connectionDescription = "Online"
        }
    }
}
