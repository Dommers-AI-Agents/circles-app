import Foundation

// MARK: - Activity Reaction Model
struct ActivityReaction: Codable {
    let id: String
    let activityId: String
    let userId: String
    let userName: String
    let userPhoto: String?
    let emoji: String
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case activityId
        case userId
        case userName
        case userPhoto
        case emoji
        case createdAt
    }
}

// MARK: - Activity Comment Model
struct ActivityComment: Codable {
    let id: String
    let activityId: String
    let userId: String
    let userName: String
    let userPhoto: String?
    let text: String
    let likes: [String]
    let likesCount: Int
    let parentCommentId: String?
    let replyCount: Int
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case activityId
        case userId
        case userName
        case userPhoto
        case text
        case likes
        case likesCount
        case parentCommentId
        case replyCount
        case createdAt
    }
    
    var isLikedByUser: Bool {
        guard let currentUserId = AuthService.shared.currentUser?.id else { return false }
        return likes.contains(currentUserId)
    }
}

// MARK: - Reaction Group Model
struct ReactionGroup: Codable {
    let emoji: String
    let count: Int
    let users: [ReactionUser]
}

struct ReactionUser: Codable {
    let userId: String
    let userName: String
    let userPhoto: String?
}

// MARK: - Reaction Response
struct ReactionsResponse: Codable {
    let success: Bool
    let data: ReactionsData
}

struct ReactionsData: Codable {
    let reactions: [ActivityReaction]
    let groups: [ReactionGroup]
    let totalCount: Int
}

// MARK: - Activity Comments Response
struct ActivityCommentsResponse: Codable {
    let success: Bool
    let data: [ActivityComment]
}

// MARK: - Supported Reaction Emojis
enum ReactionEmoji: String, CaseIterable {
    case heart = "❤️"
    case love = "😍"
    case laugh = "😂"
    case wow = "😮"
    case thumbsUp = "👍"
    case fire = "🔥"
    case party = "🎉"
    case clap = "👏"
    
    var displayName: String {
        switch self {
        case .heart: return "Like"
        case .love: return "Love"
        case .laugh: return "Haha"
        case .wow: return "Wow"
        case .thumbsUp: return "Good"
        case .fire: return "Fire"
        case .party: return "Celebrate"
        case .clap: return "Applaud"
        }
    }
}