import Foundation

enum ConnectionStatus: String, Codable {
    case pending
    case accepted
    case blocked
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .accepted: return "Connected"
        case .blocked: return "Blocked"
        }
    }
}

struct Connection: Codable, Identifiable {
    let id: String
    let userId: String
    let connectedUserId: String
    let connectedUser: User? // Populated when fetching connections
    let status: ConnectionStatus
    let sharedCircles: [String]? // Circle IDs shared with this connection
    let createdAt: Date
    let acceptedAt: Date?
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId, connectedUserId, connectedUser, status
        case sharedCircles, createdAt, acceptedAt, updatedAt
    }
    
    // Helper computed properties
    var isAccepted: Bool {
        return status == .accepted
    }
    
    var isPending: Bool {
        return status == .pending
    }
    
    var sharedCircleCount: Int {
        return sharedCircles?.count ?? 0
    }
}

// Connection request model for sending invitations
struct ConnectionRequest: Codable {
    let targetUserId: String
    let message: String?
}