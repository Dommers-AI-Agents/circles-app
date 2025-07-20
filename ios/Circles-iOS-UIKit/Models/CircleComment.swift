import Foundation

struct CircleComment: Codable, Identifiable {
    let id: String
    let circleId: String
    let userId: String
    let text: String
    let likes: [String]?
    let likesCount: Int?
    let user: User? // Populated when fetching comments
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case circleId, userId, text, likes, likesCount, user, createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        circleId = try container.decode(String.self, forKey: .circleId)
        userId = try container.decode(String.self, forKey: .userId)
        text = try container.decode(String.self, forKey: .text)
        likes = try container.decodeIfPresent([String].self, forKey: .likes)
        likesCount = try container.decodeIfPresent(Int.self, forKey: .likesCount)
        user = try container.decodeIfPresent(User.self, forKey: .user)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
    
    // Manual initializer for creating comments in code
    init(id: String, circleId: String, userId: String, text: String,
         likes: [String]? = nil, likesCount: Int? = nil, user: User? = nil, createdAt: Date) {
        self.id = id
        self.circleId = circleId
        self.userId = userId
        self.text = text
        self.likes = likes
        self.likesCount = likesCount
        self.user = user
        self.createdAt = createdAt
    }
    
    // Helper computed properties
    var isLikedByCurrentUser: Bool {
        guard let likes = likes, let currentUserId = AuthService.shared.getUserId() else { return false }
        return likes.contains(currentUserId)
    }
    
    var displayLikesCount: Int {
        return likesCount ?? 0
    }
    
    var isMyComment: Bool {
        return userId == AuthService.shared.getUserId()
    }
    
    var displayAuthorName: String {
        if isMyComment {
            return "You"
        } else if let user = user {
            return user.displayName
        }
        return "Unknown"
    }
}