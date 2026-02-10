import Foundation
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var status: NWPath.Status = .requiresConnection
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var connectionTypeText: String = "No Network"
    @Published private(set) var isExpensive: Bool = false
    @Published private(set) var isConstrained: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "tesla.subdash.network.monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.apply(path)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    private func apply(_ path: NWPath) {
        status = path.status
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        connectionTypeText = interfaceName(from: path)
    }

    private func interfaceName(from path: NWPath) -> String {
        if path.status != .satisfied {
            return "No Network"
        }
        if path.usesInterfaceType(.wifi) {
            return "Wi-Fi"
        }
        if path.usesInterfaceType(.cellular) {
            return "Cellular"
        }
        if path.usesInterfaceType(.wiredEthernet) {
            return "Ethernet"
        }
        if path.usesInterfaceType(.loopback) {
            return "Loopback"
        }
        return "Other"
    }
}
