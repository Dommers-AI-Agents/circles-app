import Foundation

// Score components breakdown
struct ScoreComponents: Codable {
    let messages: Double
    let engagement: Double
    let content: Double
    let recency: Double
    let total: Double
}

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
    let lastInteractionAt: Date?
    let interactionCount: Int?
    let lastAccessedCircles: [CircleAccess]?
    let recentActivity: [UserActivity]?
    var hasNewActivity: Bool?
    let viewCount: Int?
    let lastViewedAt: Date?
    let totalPlaces: Int? // Populated by backend
    var hasRecentPlace: Bool? // Populated by backend
    let lastMessageAt: Date? // Timestamp of last message exchanged
    let lastMessageSenderId: String? // ID of who sent the last message  
    let hasRecentMessage: Bool? // If message was within last 7 days
    let connectionScore: Double? // Weighted score calculated by backend
    let scoreComponents: ScoreComponents? // Breakdown of score components
    let scoreLastCalculated: Date? // When score was last calculated
    let createdAt: Date?
    let acceptedAt: Date?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId, connectedUserId, connectedUser, status
        case sharedCircles, lastInteractionAt, interactionCount
        case lastAccessedCircles, recentActivity, hasNewActivity
        case viewCount, lastViewedAt, totalPlaces, hasRecentPlace
        case lastMessageAt, lastMessageSenderId, hasRecentMessage
        case connectionScore, scoreComponents, scoreLastCalculated
        case createdAt, acceptedAt, updatedAt
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
    
    // Get the other user's ID (not the current user)
    func otherUserId(currentUserId: String) -> String {
        return userId == currentUserId ? connectedUserId : userId
    }
}

// Circle access tracking
struct CircleAccess: Codable {
    let circleId: String
    let accessedAt: Date?
}

// User activity tracking
struct UserActivity: Codable {
    let type: ActivityType
    let entityId: String? // Made optional for check-in activities
    let circleId: String?
    let createdAt: Date?
    
    enum ActivityType: String, Codable {
        case circle = "circle"
        case place = "place"
        case checkIn = "check_in"
    }
}

// Connection request model for sending invitations
struct ConnectionRequest: Codable {
    let targetUserId: String
    let message: String?
}