import Foundation

// MARK: - Activity Type
enum ActivityType: String, Codable {
    case placeAdded = "place_added"
    case placeLiked = "place_liked"
    case placeCommented = "place_commented"
    case circleCreated = "circle_created"
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
    }
}

// MARK: - Activity Metadata
struct ActivityMetadata: Codable {
    let comment: String?
    let placePhoto: String?
    let placeAddress: String?
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
        }
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}