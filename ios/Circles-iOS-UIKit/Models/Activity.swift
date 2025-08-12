import Foundation

// MARK: - Activity Type
enum ActivityType: String, Codable {
    case placeAdded = "place_added"
    case placeLiked = "place_liked"
    case placeCommented = "place_commented"
    case circleCreated = "circle_created"
    case commentLiked = "comment_liked"
    case checkIn = "check_in"
    case videoUploaded = "video_uploaded"
}

// MARK: - Activity Model
struct Activity: Codable {
    let id: String
    let type: ActivityType
    let actorId: String
    let actor: User?
    let targetType: String
    let targetId: String
    let targetName: String
    let circleId: String?
    let circleName: String?
    let metadata: ActivityMetadata?
    let timestamp: Date
    let isRead: Bool
    let reactionCount: Int?
    let commentCount: Int?
    let userReaction: String? // Current user's reaction emoji
    let reactionSummary: [ReactionSummary]? // Top reactions with counts
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case actorId
        case actor
        case targetType
        case targetId
        case targetName
        case circleId
        case circleName
        case metadata
        case timestamp
        case isRead
        case reactionCount
        case commentCount
        case userReaction
        case reactionSummary
    }
    
    // Check if user has reacted
    var hasUserReacted: Bool {
        return userReaction != nil
    }
    
    // Get user's reaction style
    var userReactionStyle: ReactionStyle? {
        guard let emoji = userReaction else { return nil }
        return ReactionStyle(emoji: emoji)
    }
}

// MARK: - Activity Metadata
struct ActivityMetadata: Codable {
    let comment: String?
    let placePhoto: String?
    let placeAddress: String?
    let placeId: String?
    let message: String?  // For check-in messages
    let endTime: String?  // For check-in end time
    let latitude: Double?  // For check-in place location
    let longitude: Double?  // For check-in place location
    let placeCategory: String?  // For check-in place category
    let circleId: String?  // For check-in circle reference
    let circleName: String?  // For check-in circle name
    let videoTitle: String?  // For video uploads
    let videoThumbnail: String?  // For video uploads
    let videoDuration: Double?  // For video uploads
}

// MARK: - Activity Helper Methods
extension Activity {
    var formattedDescription: String {
        switch type {
        case .placeAdded:
            return "added \(targetName) to \(circleName ?? "a circle")"
        case .placeLiked:
            return "liked \(targetName)"
        case .placeCommented:
            return "commented on \(targetName)"
        case .circleCreated:
            return "created a new circle \(targetName)"
        case .commentLiked:
            return "liked a comment on \(targetName)"
        case .checkIn:
            return "checked in at \(targetName)"
        case .videoUploaded:
            return "uploaded a video at \(targetName)"
        }
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}