import Foundation

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
    let createdAt: Date
    let connectionStatus: String? // "connected", "pending", or nil
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email, displayName, firstName, lastName, phoneNumber, profilePicture, bio, location, friends, friendRequests, circleOrder, createdAt, connectionStatus
    }
    
    // Convenience initializer for creating User objects directly
    init(id: String, email: String, displayName: String, firstName: String? = nil, lastName: String? = nil, phoneNumber: String? = nil, profilePicture: String?, bio: String?, location: String?, friends: [String]?, friendRequests: [String]?, circleOrder: [String]? = nil, createdAt: Date, connectionStatus: String? = nil) {
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
        self.createdAt = createdAt
        self.connectionStatus = connectionStatus
    }
    
    // Custom decoder for JSON decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
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
        connectionStatus = try container.decodeIfPresent(String.self, forKey: .connectionStatus)
        
        // Custom date decoding with multiple format support
        let dateString = try container.decode(String.self, forKey: .createdAt)
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
                throw DecodingError.dataCorruptedError(forKey: .createdAt, in: container, debugDescription: "Date string does not match expected format")
            }
        }
    }
}
