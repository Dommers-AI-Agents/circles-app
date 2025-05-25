import Foundation
import Network

class NetworkMonitor {
    static let shared = NetworkMonitor()
    
    private let networkMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitorQueue")
    
    private(set) var isConnected = true
    private(set) var connectionType: ConnectionType = .unknown
    
    // Observers that want to be notified of network status changes
    private var observers: [String: (Bool) -> Void] = [:]
    
    private var lastNotificationTime: Date = Date()
    private let notificationThrottle: TimeInterval = 1.0 // Minimum 1 second between notifications
    
    private init() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            let newConnected = path.status == .satisfied
            let connectionChanged = newConnected != self.isConnected
            
            self.isConnected = newConnected
            self.getConnectionType(path)
            
            // Only notify if connection status actually changed or enough time has passed
            let now = Date()
            if connectionChanged || now.timeIntervalSince(self.lastNotificationTime) >= self.notificationThrottle {
                self.lastNotificationTime = now
                
                // Notify observers on the main thread but with slight delay to avoid rapid updates
                DispatchQueue.main.async {
                    self.notifyObservers()
                }
            }
        }
        
        networkMonitor.start(queue: queue)
    }
    
    private func getConnectionType(_ path: NWPath) {
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
    
    // MARK: - Public methods
    
    func addObserver(id: String, observer: @escaping (Bool) -> Void) {
        observers[id] = observer
        // Immediately notify with current state
        observer(isConnected)
    }
    
    func removeObserver(id: String) {
        observers.removeValue(forKey: id)
    }
    
    private func notifyObservers() {
        for (_, observer) in observers {
            observer(isConnected)
        }
    }
    
    func stopMonitoring() {
        networkMonitor.cancel()
    }
}

enum ConnectionType {
    case wifi
    case cellular
    case ethernet
    case unknown
}