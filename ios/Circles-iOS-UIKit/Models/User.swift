import Foundation

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let displayName: String
    let profilePicture: String?
    let bio: String?
    let location: String?
    let friends: [String]?
    let friendRequests: [String]?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email, displayName, profilePicture, bio, location, friends, friendRequests, createdAt
    }
    
    // Convenience initializer for creating User objects directly
    init(id: String, email: String, displayName: String, profilePicture: String?, bio: String?, location: String?, friends: [String]?, friendRequests: [String]?, createdAt: Date) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.profilePicture = profilePicture
        self.bio = bio
        self.location = location
        self.friends = friends
        self.friendRequests = friendRequests
        self.createdAt = createdAt
    }
    
    // Custom decoder for JSON decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        profilePicture = try container.decodeIfPresent(String.self, forKey: .profilePicture)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        friends = try container.decodeIfPresent([String].self, forKey: .friends)
        friendRequests = try container.decodeIfPresent([String].self, forKey: .friendRequests)
        
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
