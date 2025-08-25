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
    case following
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .accepted: return "Connected"
        case .blocked: return "Blocked"
        case .following: return "Following"
        }
    }
}

struct Connection: Codable, Identifiable {
    let id: String
    let userId: String
    let connectedUserId: String
    let connectedUser: User? // Populated when fetching connections
    let status: ConnectionStatus
    let relationshipType: String? // "connection" or "following"
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
        case plainId = "id"
        case userId, connectedUserId, connectedUser, status, relationshipType
        case sharedCircles, lastInteractionAt, interactionCount
        case lastAccessedCircles, recentActivity, hasNewActivity
        case viewCount, lastViewedAt, totalPlaces, hasRecentPlace
        case lastMessageAt, lastMessageSenderId, hasRecentMessage
        case connectionScore, scoreComponents, scoreLastCalculated
        case createdAt, acceptedAt, updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode ID from either "_id" or "id" field
        if let idValue = try? container.decode(String.self, forKey: .id) {
            self.id = idValue
        } else if let plainIdValue = try? container.decode(String.self, forKey: .plainId) {
            self.id = plainIdValue
        } else {
            throw DecodingError.keyNotFound(CodingKeys.id, 
                DecodingError.Context(codingPath: decoder.codingPath, 
                                    debugDescription: "No value found for key '_id' or 'id'"))
        }
        
        // Decode all other fields normally
        userId = try container.decode(String.self, forKey: .userId)
        connectedUserId = try container.decode(String.self, forKey: .connectedUserId)
        connectedUser = try container.decodeIfPresent(User.self, forKey: .connectedUser)
        status = try container.decode(ConnectionStatus.self, forKey: .status)
        relationshipType = try container.decodeIfPresent(String.self, forKey: .relationshipType)
        sharedCircles = try container.decodeIfPresent([String].self, forKey: .sharedCircles)
        lastInteractionAt = try container.decodeIfPresent(Date.self, forKey: .lastInteractionAt)
        interactionCount = try container.decodeIfPresent(Int.self, forKey: .interactionCount)
        lastAccessedCircles = try container.decodeIfPresent([CircleAccess].self, forKey: .lastAccessedCircles)
        recentActivity = try container.decodeIfPresent([UserActivity].self, forKey: .recentActivity)
        hasNewActivity = try container.decodeIfPresent(Bool.self, forKey: .hasNewActivity)
        viewCount = try container.decodeIfPresent(Int.self, forKey: .viewCount)
        lastViewedAt = try container.decodeIfPresent(Date.self, forKey: .lastViewedAt)
        totalPlaces = try container.decodeIfPresent(Int.self, forKey: .totalPlaces)
        hasRecentPlace = try container.decodeIfPresent(Bool.self, forKey: .hasRecentPlace)
        lastMessageAt = try container.decodeIfPresent(Date.self, forKey: .lastMessageAt)
        lastMessageSenderId = try container.decodeIfPresent(String.self, forKey: .lastMessageSenderId)
        hasRecentMessage = try container.decodeIfPresent(Bool.self, forKey: .hasRecentMessage)
        connectionScore = try container.decodeIfPresent(Double.self, forKey: .connectionScore)
        scoreComponents = try container.decodeIfPresent(ScoreComponents.self, forKey: .scoreComponents)
        scoreLastCalculated = try container.decodeIfPresent(Date.self, forKey: .scoreLastCalculated)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        acceptedAt = try container.decodeIfPresent(Date.self, forKey: .acceptedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode ID to both fields for compatibility
        try container.encode(id, forKey: .id)
        try container.encode(id, forKey: .plainId)
        
        // Encode all other fields
        try container.encode(userId, forKey: .userId)
        try container.encode(connectedUserId, forKey: .connectedUserId)
        try container.encodeIfPresent(connectedUser, forKey: .connectedUser)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(relationshipType, forKey: .relationshipType)
        try container.encodeIfPresent(sharedCircles, forKey: .sharedCircles)
        try container.encodeIfPresent(lastInteractionAt, forKey: .lastInteractionAt)
        try container.encodeIfPresent(interactionCount, forKey: .interactionCount)
        try container.encodeIfPresent(lastAccessedCircles, forKey: .lastAccessedCircles)
        try container.encodeIfPresent(recentActivity, forKey: .recentActivity)
        try container.encodeIfPresent(hasNewActivity, forKey: .hasNewActivity)
        try container.encodeIfPresent(viewCount, forKey: .viewCount)
        try container.encodeIfPresent(lastViewedAt, forKey: .lastViewedAt)
        try container.encodeIfPresent(totalPlaces, forKey: .totalPlaces)
        try container.encodeIfPresent(hasRecentPlace, forKey: .hasRecentPlace)
        try container.encodeIfPresent(lastMessageAt, forKey: .lastMessageAt)
        try container.encodeIfPresent(lastMessageSenderId, forKey: .lastMessageSenderId)
        try container.encodeIfPresent(hasRecentMessage, forKey: .hasRecentMessage)
        try container.encodeIfPresent(connectionScore, forKey: .connectionScore)
        try container.encodeIfPresent(scoreComponents, forKey: .scoreComponents)
        try container.encodeIfPresent(scoreLastCalculated, forKey: .scoreLastCalculated)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(acceptedAt, forKey: .acceptedAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
    
    // Helper computed properties
    var isAccepted: Bool {
        return status == .accepted
    }
    
    var isPending: Bool {
        return status == .pending
    }
    
    var isFollowing: Bool {
        return relationshipType == "following"
    }
    
    var isConnection: Bool {
        return relationshipType == "connection" || relationshipType == nil
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