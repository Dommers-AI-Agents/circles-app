import Foundation
import Network

class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    private(set) var isConnected = true
    private(set) var connectionType: ConnectionType = .unknown
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var observers: [String: (Bool) -> Void] = [:]
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.updateConnectionType(path)
                
                // Notify all observers
                self?.observers.forEach { _, handler in
                    handler(path.status == .satisfied)
                }
            }
        }
        
        monitor.start(queue: queue)
    }
    
    private func updateConnectionType(_ path: NWPath) {
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else {
            connectionType = .unknown
        }
    }
    
    func addObserver(id: String, handler: @escaping (Bool) -> Void) {
        observers[id] = handler
        // Immediately notify with current state
        handler(isConnected)
    }
    
    func removeObserver(id: String) {
        observers.removeValue(forKey: id)
    }
    
    deinit {
        monitor.cancel()
    }
}

enum ConnectionType {
    case wifi
    case cellular
    case ethernet
    case unknown
}

