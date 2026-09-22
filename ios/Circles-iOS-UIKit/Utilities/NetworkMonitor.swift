import Foundation
import Network

class NetworkMonitor {
    static let shared = NetworkMonitor()
    /// `userInfo` key on `.networkReachabilityDidChange`: the new `isConnected`.
    static let isConnectedKey = "isConnected"
    
    private(set) var isConnected = true
    private(set) var connectionType: ConnectionType = .unknown
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var observers: [String: (Bool) -> Void] = [:]
    private var lastConnectionState = true
    private var suppressLogging = false
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                let newState = path.status == .satisfied
                let stateChanged = newState != self.lastConnectionState
                
                self.isConnected = newState
                self.updateConnectionType(path)
                
                // Only log significant changes, not every check
                if stateChanged && !self.suppressLogging {
                    if newState {
                        Logger.info("Network connection restored: \(self.connectionType)")
                    } else {
                        Logger.warning("Network connection lost")
                    }
                }
                
                self.lastConnectionState = newState
                
                // Notify all observers only on state change
                if stateChanged {
                    self.observers.forEach { _, handler in
                        handler(newState)
                    }
                    NotificationCenter.default.post(name: .networkReachabilityDidChange, object: nil,
                                                    userInfo: [NetworkMonitor.isConnectedKey: newState])
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


extension Notification.Name {
    /// Posted on the main queue when the path changes between reachable and
    /// not (never for every path update). Queues drain on the way back up;
    /// the offline banner shows on the way down.
    static let networkReachabilityDidChange = Notification.Name("NetworkReachabilityDidChange")
}
