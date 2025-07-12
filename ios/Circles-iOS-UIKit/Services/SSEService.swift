import Foundation

// MARK: - SSE Event Types
enum SSEEventType: String {
    case connected = "connected"
    case connectionRequest = "connection_request"
    case connectionAccepted = "connection_accepted"
    case connectionDeclined = "connection_declined"
    case newMessage = "new_message"
    case newSuggestion = "new_suggestion"
    case followerAdded = "follower_added"
    case followerRemoved = "follower_removed"
    case followingAdded = "following_added"
    case followingRemoved = "following_removed"
    case newActivity = "new_activity"
}

// MARK: - SSE Event
struct SSEEvent {
    let type: SSEEventType
    let data: [String: Any]
    let timestamp: Date
}

// MARK: - SSE Service Delegate
protocol SSEServiceDelegate: AnyObject {
    func sseService(_ service: SSEService, didReceiveEvent event: SSEEvent)
    func sseServiceDidConnect(_ service: SSEService)
    func sseServiceDidDisconnect(_ service: SSEService, error: Error?)
}

// MARK: - SSE Service
class SSEService: NSObject {
    static let shared = SSEService()
    
    // MARK: - Properties
    private var eventSource: URLSessionDataTask?
    private var session: URLSession?
    private var isConnected = false
    private var reconnectTimer: Timer?
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 30.0
    
    // Delegates management
    private var delegates = NSHashTable<AnyObject>.weakObjects()
    
    // Buffer for incomplete data
    private var dataBuffer = ""
    
    private override init() {
        super.init()
        setupSession()
        setupAuthListener()
    }
    
    // MARK: - Public Methods
    
    func addDelegate(_ delegate: SSEServiceDelegate) {
        delegates.add(delegate)
    }
    
    func removeDelegate(_ delegate: SSEServiceDelegate) {
        delegates.remove(delegate)
    }
    
    func connect() {
        guard AuthService.shared.isLoggedIn,
              let token = AuthService.shared.getToken() else {
            print("📡 SSE: Cannot connect - user not authenticated")
            return
        }
        
        if isConnected {
            print("📡 SSE: Already connected")
            return
        }
        
        // Cancel any pending reconnect
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        // Create SSE request with correct base URL
        // Using production URL directly since APIService uses production even in DEBUG
        #if DEBUG
        let baseURL = "https://circles-backend-196924649787.us-central1.run.app/api"
        #else
        let baseURL = "https://circles-backend-196924649787.us-central1.run.app/api"
        #endif
        
        guard let url = URL(string: "\(baseURL)/sse/stream") else {
            print("📡 SSE: Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = TimeInterval.infinity
        
        print("📡 SSE: Connecting to \(url)")
        
        // Create data task
        eventSource = session?.dataTask(with: request)
        eventSource?.resume()
        
        isConnected = true
        notifyDelegatesDidConnect()
    }
    
    func disconnect() {
        print("📡 SSE: Disconnecting")
        
        eventSource?.cancel()
        eventSource = nil
        isConnected = false
        
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        
        dataBuffer = ""
        
        notifyDelegatesDidDisconnect(error: nil)
    }
    
    // MARK: - Private Methods
    
    private func setupSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = TimeInterval.infinity
        config.timeoutIntervalForResource = TimeInterval.infinity
        
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }
    
    private func setupAuthListener() {
        AuthService.shared.addAuthStateListener(id: "SSEService") { [weak self] isAuthenticated in
            if isAuthenticated {
                self?.connect()
            } else {
                self?.disconnect()
            }
        }
    }
    
    private func handleReconnect() {
        guard AuthService.shared.isLoggedIn else { return }
        
        // Exponential backoff
        reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
        
        print("📡 SSE: Reconnecting in \(reconnectDelay) seconds")
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
    
    private func processEventData(_ data: String) {
        // Split by double newline to separate events
        let events = data.components(separatedBy: "\n\n")
        
        for eventString in events {
            guard !eventString.isEmpty else { continue }
            
            // Parse event
            var eventData: String?
            
            let lines = eventString.components(separatedBy: "\n")
            for line in lines {
                if line.hasPrefix("data: ") {
                    eventData = String(line.dropFirst(6))
                } else if line.hasPrefix(":") {
                    // Comment line (like heartbeat), ignore
                    continue
                }
            }
            
            // Process event data
            if let eventData = eventData,
               let jsonData = eventData.data(using: .utf8) {
                do {
                    if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let typeString = json["type"] as? String,
                       let eventType = SSEEventType(rawValue: typeString) {
                        
                        let event = SSEEvent(
                            type: eventType,
                            data: json["data"] as? [String: Any] ?? [:],
                            timestamp: Date()
                        )
                        
                        DispatchQueue.main.async { [weak self] in
                            self?.notifyDelegatesDidReceiveEvent(event)
                        }
                        
                        // Reset reconnect delay on successful event
                        reconnectDelay = 1.0
                    }
                } catch {
                    print("📡 SSE: Error parsing event data: \(error)")
                }
            }
        }
    }
    
    // MARK: - Delegate Notifications
    
    private func notifyDelegatesDidConnect() {
        delegates.allObjects.forEach { delegate in
            (delegate as? SSEServiceDelegate)?.sseServiceDidConnect(self)
        }
    }
    
    private func notifyDelegatesDidDisconnect(error: Error?) {
        delegates.allObjects.forEach { delegate in
            (delegate as? SSEServiceDelegate)?.sseServiceDidDisconnect(self, error: error)
        }
    }
    
    private func notifyDelegatesDidReceiveEvent(_ event: SSEEvent) {
        delegates.allObjects.forEach { delegate in
            (delegate as? SSEServiceDelegate)?.sseService(self, didReceiveEvent: event)
        }
    }
}

// MARK: - URLSessionDataDelegate
extension SSEService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            print("📡 SSE: Response received with status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                completionHandler(.allow)
            } else {
                completionHandler(.cancel)
                isConnected = false
                handleReconnect()
            }
        } else {
            completionHandler(.allow)
        }
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        
        // Add to buffer
        dataBuffer += string
        
        // Process complete events (ending with double newline)
        while let range = dataBuffer.range(of: "\n\n") {
            let eventData = String(dataBuffer[..<range.lowerBound])
            dataBuffer.removeSubrange(..<range.upperBound)
            
            if !eventData.isEmpty {
                processEventData(eventData + "\n\n")
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        print("📡 SSE: Connection completed with error: \(error?.localizedDescription ?? "none")")
        
        isConnected = false
        dataBuffer = ""
        
        notifyDelegatesDidDisconnect(error: error)
        
        // Attempt reconnect if it wasn't a manual disconnect
        if error != nil && AuthService.shared.isLoggedIn {
            handleReconnect()
        }
    }
}

// MARK: - URLSessionDelegate
extension SSEService: URLSessionDelegate {
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        print("📡 SSE: Session became invalid: \(error?.localizedDescription ?? "unknown error")")
        isConnected = false
        handleReconnect()
    }
}