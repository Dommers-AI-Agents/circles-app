import Foundation

struct UserPreferences: Codable {
    let defaultHomeView: String? // "list" or "map"
}

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let firstName: String?
    let lastName: String?
    let phoneNumber: String?
    let profilePicture: String?
    let bio: String?
    let location: String?
    let friends: [String]?
    let friendRequests: [String]?
    let circleOrder: [String]?
    let preferences: UserPreferences?
    let createdAt: Date?
    let connectionStatus: String? // "connected", "pending", or nil
    let connectionDirection: String? // "incoming" or "outgoing" for pending connections
    let connectionId: String? // ID of the connection document
    
    // Instagram-style follower system
    let followers: [String]?
    let following: [String]?
    let followersCount: Int?
    let followingCount: Int?
    
    // Connections count (LinkedIn-style professional network)
    let connectionsCount: Int?
    
    // Pinned places (max 6)
    let pinnedPlaces: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email, displayName, firstName, lastName, phoneNumber, profilePicture, bio, location, friends, friendRequests, circleOrder, preferences, createdAt, connectionStatus, connectionDirection, connectionId, followers, following, followersCount, followingCount, connectionsCount, pinnedPlaces
    }
    
    // Convenience initializer for creating User objects directly
    init(id: String, email: String, displayName: String, firstName: String? = nil, lastName: String? = nil, phoneNumber: String? = nil, profilePicture: String?, bio: String?, location: String?, friends: [String]?, friendRequests: [String]?, circleOrder: [String]? = nil, preferences: UserPreferences? = nil, createdAt: Date? = nil, connectionStatus: String? = nil, connectionDirection: String? = nil, connectionId: String? = nil, followers: [String]? = nil, following: [String]? = nil, followersCount: Int? = nil, followingCount: Int? = nil, connectionsCount: Int? = nil, pinnedPlaces: [String]? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber
        self.profilePicture = profilePicture
        self.bio = bio
        self.location = location
        self.friends = friends
        self.friendRequests = friendRequests
        self.circleOrder = circleOrder
        self.preferences = preferences
        self.createdAt = createdAt
        self.connectionStatus = connectionStatus
        self.connectionDirection = connectionDirection
        self.connectionId = connectionId
        self.followers = followers
        self.following = following
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.connectionsCount = connectionsCount
        self.pinnedPlaces = pinnedPlaces
    }
    
    // Custom decoder for JSON decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode id with flexible field names (_id or id)
        if let id = try? container.decode(String.self, forKey: .id) {
            self.id = id
        } else {
            // Try to decode with dynamic key "id" (without underscore)
            struct DynamicCodingKeys: CodingKey {
                var stringValue: String
                var intValue: Int? { nil }
                
                init(stringValue: String) {
                    self.stringValue = stringValue
                }
                
                init?(intValue: Int) {
                    return nil
                }
            }
            
            let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKeys.self)
            if let id = try? dynamicContainer.decode(String.self, forKey: DynamicCodingKeys(stringValue: "id")) {
                self.id = id
            } else {
                throw DecodingError.keyNotFound(CodingKeys.id, 
                    DecodingError.Context(codingPath: decoder.codingPath, 
                                        debugDescription: "No value found for key '_id' or 'id'"))
            }
        }
        
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        profilePicture = try container.decodeIfPresent(String.self, forKey: .profilePicture)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        friends = try container.decodeIfPresent([String].self, forKey: .friends)
        friendRequests = try container.decodeIfPresent([String].self, forKey: .friendRequests)
        circleOrder = try container.decodeIfPresent([String].self, forKey: .circleOrder)
        preferences = try container.decodeIfPresent(UserPreferences.self, forKey: .preferences)
        connectionStatus = try container.decodeIfPresent(String.self, forKey: .connectionStatus)
        connectionDirection = try container.decodeIfPresent(String.self, forKey: .connectionDirection)
        connectionId = try container.decodeIfPresent(String.self, forKey: .connectionId)
        
        // Instagram-style follower system
        followers = try container.decodeIfPresent([String].self, forKey: .followers)
        following = try container.decodeIfPresent([String].self, forKey: .following)
        followersCount = try container.decodeIfPresent(Int.self, forKey: .followersCount)
        followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount)
        
        // Connections count (LinkedIn-style professional network)
        connectionsCount = try container.decodeIfPresent(Int.self, forKey: .connectionsCount)
        
        // Pinned places
        pinnedPlaces = try container.decodeIfPresent([String].self, forKey: .pinnedPlaces)
        
        // Custom date decoding with multiple format support
        if let dateString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            if let date = formatter.date(from: dateString) {
                createdAt = date
            } else {
                // Fallback to basic ISO8601 format
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: dateString) {
                    createdAt = date
                } else {
                    createdAt = nil
                }
            }
        } else {
            createdAt = nil
        }
    }
}
