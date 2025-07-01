import Foundation
import Combine

class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    
    @Published var connections: [Connection] = []
    @Published var pendingConnections: [Connection] = []
    @Published var sharedCircles: [CircleShare] = []
    @Published var editableCirclesFromOthers: [Circle] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let apiService = APIService.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Defer setup until Firebase is configured
    }
    
    func configure() {
        setupSubscribers()
    }
    
    private func setupSubscribers() {
        // Listen for authentication changes
        AuthManager.shared.$isAuthenticated
            .sink { [weak self] isAuthenticated in
                if isAuthenticated {
                    self?.loadNetworkData()
                } else {
                    self?.clearData()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    
    func loadNetworkData() {
        loadConnections()
        loadSharedCircles()
    }
    
    // MARK: - Get Connections as Users
    
    func getConnections(completion: @escaping (Result<[User], Error>) -> Void) {
        // If connections are already loaded, return them
        if !connections.isEmpty {
            let users = connections.compactMap { $0.connectedUser }
            completion(.success(users))
            return
        }
        
        // Otherwise, load connections first
        apiService.request(
            endpoint: "connections",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<ConnectionsResponse, APIError>) in
            switch result {
            case .success(let response):
                let acceptedConnections = response.connections.filter { $0.status == .accepted }
                let users = acceptedConnections.compactMap { $0.connectedUser }
                self?.connections = acceptedConnections
                completion(.success(users))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func loadConnections() {
        isLoading = true
        
        apiService.request(
            endpoint: "connections",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<ConnectionsResponse, APIError>) in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                switch result {
                case .success(let response):
                    let connections = response.connections
                    self?.connections = connections.filter { $0.status == .accepted }
                    self?.pendingConnections = connections.filter { $0.status == .pending }
                    
                    // Post notification after data is loaded
                    NotificationCenter.default.post(
                        name: Notification.Name("PendingConnectionsCountChanged"),
                        object: nil
                    )
                case .failure(let error):
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    func loadSharedCircles() {
        apiService.request(
            endpoint: "network/shared-circles",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<CircleSharesResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    // Handle both old format (shares) and new format (data)
                    if !response.shares.isEmpty {
                        self?.sharedCircles = response.shares
                    } else if let circlesData = response.data {
                        // Convert circles to shares if needed
                        print("✅ Loaded \(circlesData.count) shared circles")
                    }
                case .failure(let error):
                    self?.error = error.localizedDescription
                }
            }
        }
        
        // Also load editable circles from others
        loadEditableCirclesFromOthers()
    }
    
    func loadEditableCirclesFromOthers() {
        struct EditableCirclesResponse: Codable {
            let success: Bool
            let data: [Circle]
        }
        
        apiService.request(
            endpoint: "network/circles-shared-with-me",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<EditableCirclesResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self?.editableCirclesFromOthers = response.data
                    print("✅ Loaded \(response.data.count) editable circles from others")
                case .failure(let error):
                    self?.error = error.localizedDescription
                    print("❌ Failed to load editable circles from others: \(error)")
                }
            }
        }
    }
    
    // MARK: - Connection Management
    
    func generateConnectionInviteLink() -> String {
        guard let userId = AuthService.shared.getUserId() else {
            print("🔗 NetworkManager: No user ID available for invite link")
            return ""
        }
        
        print("🔗 NetworkManager: Generating connection invite link")
        print("🔗 NetworkManager: Current user ID from AuthService: \(userId)")
        print("🔗 NetworkManager: Current user from AuthManager: \(AuthManager.shared.currentUser?.id ?? "nil")")
        
        // Parse the user ID to ensure we use simple format in the link
        var simpleUserId = userId
        if userId.contains(".") {
            let components = userId.components(separatedBy: ".")
            if components.count >= 2 {
                simpleUserId = components[1] // Extract the Firebase UID part
                print("🔗 NetworkManager: Extracted simple ID \(simpleUserId) from complex ID \(userId)")
            }
        }
        
        // Create the deep link URL with the simple user ID
        let inviteLink = "circles://connect/\(simpleUserId)"
        print("🔗 NetworkManager: Generated invite link: \(inviteLink)")
        
        return inviteLink
    }
    
    func shareConnectionInvite() -> [Any] {
        guard let currentUser = AuthManager.shared.currentUser else {
            return ["Join me on Circles!"]
        }
        
        let userId = currentUser.id
        let userName = currentUser.displayName
        
        // Parse the user ID to ensure we use simple format in the link
        var simpleUserId = userId
        if userId.contains(".") {
            let components = userId.components(separatedBy: ".")
            if components.count >= 2 {
                simpleUserId = components[1] // Extract the Firebase UID part
                print("🔗 NetworkManager: shareConnectionInvite - Extracted simple ID \(simpleUserId) from complex ID \(userId)")
            }
        }
        
        // Create invite text
        var shareText = "\(userName) wants to connect with you on Circles!"
        shareText += "\n\n🔗 Join my network to share favorite places and discover new ones together."
        
        // Add deep link with simple user ID
        let deepLink = "circles://connect/\(simpleUserId)"
        shareText += "\n\n📱 Connect with me: \(deepLink)"
        
        // Add app store link
        let appStoreLink = "https://testflight.apple.com/join/n1sBRMG3"
        shareText += "\n\nDon't have Circles? Download here: \(appStoreLink)"
        
        return [shareText]
    }
    
    func sendConnectionRequest(to userId: String, message: String? = nil, autoAccept: Bool = false, completion: @escaping (Result<Connection, Error>) -> Void) {
        print("📤 NetworkManager: Sending connection request to userId: \(userId)")
        var body: [String: Any] = ["targetUserId": userId]
        if let message = message {
            body["message"] = message
        }
        if autoAccept {
            body["autoAccept"] = true
        }
        print("📤 NetworkManager: Request body: \(body)")
        
        apiService.request(
            endpoint: "connections/invite",
            method: .post,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<ConnectionResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if let connection = response.data {
                        // Add to appropriate list based on status
                        if connection.status == .accepted {
                            self?.connections.append(connection)
                        } else {
                            self?.pendingConnections.append(connection)
                        }
                        completion(.success(connection))
                    } else {
                        completion(.failure(APIError.invalidResponse))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    func handleConnectionInvite(from inviteUserId: String, completion: @escaping (Result<Connection, Error>) -> Void) {
        print("🔗 NetworkManager: handleConnectionInvite called with userId: \(inviteUserId)")
        
        // Parse userId from deep link format
        // Format could be: "userId" or "prefix.userId.suffix" or "userId_timestamp"
        var cleanUserId = inviteUserId
        
        // First check if it contains dots (new format)
        if inviteUserId.contains(".") {
            let components = inviteUserId.components(separatedBy: ".")
            // The actual Firebase UID is likely the middle component in format like "000454.9b5eeac93282416c9bc6dcecbc49b40f.2127"
            if components.count >= 2 {
                // Use the second component which should be the Firebase UID
                cleanUserId = components[1]
            }
        } else if inviteUserId.contains("_") {
            // Fallback to old format with underscore
            cleanUserId = inviteUserId.components(separatedBy: "_").first ?? inviteUserId
        }
        
        print("🔗 NetworkManager: Cleaned userId: \(cleanUserId) from original: \(inviteUserId)")
        
        // Check if it's the current user
        if cleanUserId == AuthService.shared.getUserId() {
            print("🔗 NetworkManager: Cannot connect to yourself")
            completion(.failure(NSError(domain: "NetworkManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot connect to yourself"])))
            return
        }
        
        // Check if already connected
        if connections.contains(where: { $0.connectedUserId == cleanUserId || $0.userId == cleanUserId }) {
            print("🔗 NetworkManager: Already connected to user \(cleanUserId)")
            completion(.failure(NSError(domain: "NetworkManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Already connected to this user"])))
            return
        }
        
        // Check if there's already a pending request
        if pendingConnections.contains(where: { $0.connectedUserId == cleanUserId || $0.userId == cleanUserId }) {
            print("🔗 NetworkManager: Connection request already pending for user \(cleanUserId)")
            completion(.failure(NSError(domain: "NetworkManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Connection request already pending"])))
            return
        }
        
        print("🔗 NetworkManager: Sending connection request to user \(cleanUserId)")
        
        // Send connection request with autoAccept = true for invite links
        sendConnectionRequest(to: cleanUserId, message: "Connected via invite link", autoAccept: true) { result in
            switch result {
            case .success(let connection):
                print("🔗 NetworkManager: Connection created successfully: \(connection.id), status: \(connection.status)")
            case .failure(let error):
                print("🔗 NetworkManager: Failed to create connection: \(error)")
            }
            completion(result)
        }
    }
    
    func acceptConnection(_ connectionId: String, completion: @escaping (Result<Connection, Error>) -> Void) {
        apiService.request(
            endpoint: "connections/\(connectionId)/accept",
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<ConnectionResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if let connection = response.data {
                        // Move from pending to accepted
                        self?.pendingConnections.removeAll { $0.id == connectionId }
                        self?.connections.append(connection)
                        completion(.success(connection))
                    } else {
                        completion(.failure(APIError.invalidResponse))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    func declineConnection(_ connectionId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        apiService.request(
            endpoint: "connections/\(connectionId)/decline",
            method: .delete,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.pendingConnections.removeAll { $0.id == connectionId }
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    func blockConnection(_ connectionId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        apiService.request(
            endpoint: "connections/\(connectionId)/block",
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.connections.removeAll { $0.id == connectionId }
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Circle Sharing
    
    func shareCircle(
        _ circleId: String,
        with userId: String?,
        email: String? = nil,
        accessLevel: AccessLevel = .viewOnly,
        expiresIn: Int? = nil,
        completion: @escaping (Result<CircleShare, Error>) -> Void
    ) {
        var body: [String: Any] = [
            "accessLevel": accessLevel.rawValue
        ]
        
        if let userId = userId {
            body["userId"] = userId
            body["shareType"] = ShareType.registeredUser.rawValue
        } else if let email = email {
            body["email"] = email
            body["shareType"] = ShareType.email.rawValue
        } else {
            body["shareType"] = ShareType.link.rawValue
        }
        
        if let expiresIn = expiresIn {
            body["expiresIn"] = expiresIn
        }
        
        apiService.request(
            endpoint: "circles/\(circleId)/share",
            method: .post,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<CircleSharesResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if let share = response.shares.first {
                        self?.sharedCircles.append(share)
                        completion(.success(share))
                    } else {
                        completion(.failure(APIError.invalidResponse))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    func revokeShare(_ shareId: String, circleId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        apiService.request(
            endpoint: "circles/\(circleId)/share/\(shareId)",
            method: .delete,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.sharedCircles.removeAll { $0.id == shareId }
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    func getCircleShares(for circleId: String, completion: @escaping (Result<[CircleShare], Error>) -> Void) {
        apiService.request(
            endpoint: "circles/\(circleId)/shares",
            method: .get,
            requiresAuth: true
        ) { (result: Result<CircleSharesResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    completion(.success(response.shares))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    func getSharedCirclesWithConnection(_ connectionId: String, completion: @escaping (Result<[Circle], Error>) -> Void) {
        apiService.request(
            endpoint: "connections/\(connectionId)/shared-circles",
            method: .get,
            requiresAuth: true
        ) { (result: Result<NetworkCirclesResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    completion(.success(response.circles))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    func isCircleSharedWith(circleId: String, userId: String) -> Bool {
        return sharedCircles.contains { share in
            share.circleId == circleId && 
            share.sharedWith == userId && 
            share.shareType == .registeredUser &&
            !share.isExpired
        }
    }
    
    func getSharesForCircle(_ circleId: String) -> [CircleShare] {
        return sharedCircles.filter { $0.circleId == circleId }
    }
    
    func getConnectionById(_ id: String) -> Connection? {
        return connections.first { $0.id == id }
    }
    
    func acceptSharedCircle(shareId: String, completion: @escaping (Result<CircleShare, Error>) -> Void) {
        apiService.request(
            endpoint: "circles/share/\(shareId)/accept",
            method: .post,
            requiresAuth: true
        ) { (result: Result<CircleSharesResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if let share = response.shares.first {
                        completion(.success(share))
                        // Reload circles to include the newly shared one
                        Task {
                            await CircleManager.shared.fetchCircles()
                        }
                    } else {
                        completion(.failure(APIError.invalidResponse))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Connection Fetching (for UIKit compatibility)
    
    func fetchConnections(completion: @escaping ([Connection]?, Error?) -> Void) {
        // Load connections from server
        apiService.request(
            endpoint: "connections",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<ConnectionsResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    let connections = response.connections
                    self?.connections = connections.filter { $0.status == .accepted }
                    self?.pendingConnections = connections.filter { $0.status == .pending }
                    // Return only accepted connections
                    completion(self?.connections, nil)
                case .failure(let error):
                    completion(nil, error)
                }
            }
        }
    }
    
    func fetchActiveConnections(limit: Int = 10, completion: @escaping ([Connection]?, Error?) -> Void) {
        // Load active connections sorted by activity
        apiService.request(
            endpoint: "connections/active?limit=\(limit)",
            method: .get,
            requiresAuth: true
        ) { (result: Result<ConnectionsResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    completion(response.connections, nil)
                case .failure(let error):
                    completion(nil, error)
                }
            }
        }
    }
    
    func clearConnectionActivity(connectionId: String, completion: @escaping (Error?) -> Void) {
        apiService.request(
            endpoint: "connections/\(connectionId)/clear-activity",
            method: .post,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    completion(nil)
                case .failure(let error):
                    completion(error)
                }
            }
        }
    }
    
    func trackConnectionView(connectionId: String, completion: @escaping (Error?) -> Void) {
        apiService.request(
            endpoint: "connections/\(connectionId)/track-view",
            method: .post,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    completion(nil)
                case .failure(let error):
                    completion(error)
                }
            }
        }
    }
    
    func removeConnection(connectionId: String, completion: @escaping (Error?) -> Void) {
        apiService.request(
            endpoint: "connections/\(connectionId)",
            method: .delete,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Remove from local list
                    self?.connections.removeAll { $0.id == connectionId }
                    self?.pendingConnections.removeAll { $0.id == connectionId }
                    completion(nil)
                case .failure(let error):
                    completion(error)
                }
            }
        }
    }
    
    private func clearData() {
        connections = []
        pendingConnections = []
        sharedCircles = []
    }
    
    // MARK: - Pending Connection Storage for New Users
    
    static func storePendingConnectionInvite(userId: String) {
        UserDefaults.standard.set(userId, forKey: "pendingConnectionInvite")
    }
    
    static func getPendingConnectionInvite() -> String? {
        return UserDefaults.standard.string(forKey: "pendingConnectionInvite")
    }
    
    static func clearPendingConnectionInvite() {
        UserDefaults.standard.removeObject(forKey: "pendingConnectionInvite")
    }
    
    func processPendingConnectionInvite() {
        guard let pendingUserId = NetworkManager.getPendingConnectionInvite() else { return }
        
        // Clear the pending invite
        NetworkManager.clearPendingConnectionInvite()
        
        // Parse userId from deep link format using same logic as handleConnectionInvite
        var cleanUserId = pendingUserId
        
        // First check if it contains dots (new format)
        if pendingUserId.contains(".") {
            let components = pendingUserId.components(separatedBy: ".")
            // The actual Firebase UID is likely the middle component
            if components.count >= 2 {
                cleanUserId = components[1]
            }
        } else if pendingUserId.contains("_") {
            // Fallback to old format with underscore
            cleanUserId = pendingUserId.components(separatedBy: "_").first ?? pendingUserId
        }
        
        print("🔗 NetworkManager: Processing pending connection - cleaned userId: \(cleanUserId) from original: \(pendingUserId)")
        
        // Process the connection invite
        handleConnectionInvite(from: cleanUserId) { result in
            switch result {
            case .success:
                print("Successfully processed pending connection invite")
                // Refresh connections list
                self.loadConnections()
            case .failure(let error):
                print("Failed to process pending connection invite: \(error)")
            }
        }
    }
    
    // MARK: - Badge Count
    
    func getPendingConnectionsCount(completion: @escaping (Int) -> Void) {
        // Return count of pending incoming connections
        let pendingCount = pendingConnections.filter { connection in
            // Count only incoming pending connections
            connection.status == .pending && connection.connectedUserId == AuthService.shared.getUserId()
        }.count
        
        completion(pendingCount)
    }
}

// Response types
struct ConnectionsResponse: Codable {
    let success: Bool
    let connections: [Connection]
    
    enum CodingKeys: String, CodingKey {
        case success
        case connections
        case data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        
        // Try to decode from 'connections' key first, fallback to 'data'
        if let connections = try? container.decode([Connection].self, forKey: .connections) {
            self.connections = connections
        } else if let data = try? container.decode([Connection].self, forKey: .data) {
            self.connections = data
        } else {
            // If neither key exists or both are empty, use empty array
            self.connections = []
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(connections, forKey: .connections)
    }
}

struct ConnectionResponse: Codable {
    let success: Bool
    let data: Connection?
    let message: String?
}

struct CircleSharesResponse: Codable {
    let success: Bool
    let shares: [CircleShare]
    let data: [Circle]?
    
    enum CodingKeys: String, CodingKey {
        case success
        case shares
        case data
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        
        // Try to decode shares if present (old format)
        if let shares = try? container.decode([CircleShare].self, forKey: .shares) {
            self.shares = shares
            self.data = nil
        } else if let data = try? container.decode([Circle].self, forKey: .data) {
            // New format with circles data
            self.data = data
            self.shares = []
        } else {
            // Default to empty arrays
            self.shares = []
            self.data = nil
        }
    }
}

struct NetworkCirclesResponse: Codable {
    let success: Bool
    let circles: [Circle]
}

// Empty response for DELETE operations
struct EmptyResponse: Codable {
    let success: Bool?
}