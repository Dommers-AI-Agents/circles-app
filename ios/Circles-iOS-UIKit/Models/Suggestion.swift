import Foundation

struct Suggestion: Codable, Identifiable {
    let id: String
    let userId: String
    let userDetails: User?
    let message: String
    let placeId: String?
    let placeDetails: Place?
    let imageUrl: String?
    let mentionedPlaces: [PlaceMention]?
    let commentsCount: Int?
    let likes: [String]?
    let likesCount: Int?
    let createdAt: Date
    let updatedAt: Date
    let expiresAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId, userDetails, message, placeId, placeDetails, imageUrl, mentionedPlaces, commentsCount
        case likes, likesCount
        case createdAt, updatedAt, expiresAt
    }
    
    // Custom decoder to handle date strings
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        userDetails = try container.decodeIfPresent(User.self, forKey: .userDetails)
        message = try container.decode(String.self, forKey: .message)
        placeId = try container.decodeIfPresent(String.self, forKey: .placeId)
        placeDetails = try container.decodeIfPresent(Place.self, forKey: .placeDetails)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        mentionedPlaces = try container.decodeIfPresent([PlaceMention].self, forKey: .mentionedPlaces)
        commentsCount = try container.decodeIfPresent(Int.self, forKey: .commentsCount)
        likes = try container.decodeIfPresent([String].self, forKey: .likes)
        likesCount = try container.decodeIfPresent(Int.self, forKey: .likesCount)
        
        // Decode dates
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        if let date = formatter.date(from: createdAtString) {
            createdAt = date
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            createdAt = formatter.date(from: createdAtString) ?? Date()
        }
        
        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)
        if let date = formatter.date(from: updatedAtString) {
            updatedAt = date
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            updatedAt = formatter.date(from: updatedAtString) ?? Date()
        }
        
        let expiresAtString = try container.decode(String.self, forKey: .expiresAt)
        if let date = formatter.date(from: expiresAtString) {
            expiresAt = date
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            expiresAt = formatter.date(from: expiresAtString) ?? Date()
        }
    }
    
    // Convenience properties
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    var isExpired: Bool {
        return expiresAt < Date()
    }
    
    var isCurrentUserSuggestion: Bool {
        return userId == AuthService.shared.getUserId()
    }
    
    var displayAuthorName: String {
        if isCurrentUserSuggestion {
            return "You"
        }
        return userDetails?.displayName ?? "Unknown User"
    }
    
    var isLikedByCurrentUser: Bool {
        guard let likes = likes, let currentUserId = AuthService.shared.getUserId() else {
            return false
        }
        return likes.contains(currentUserId)
    }
    
    var likesCountDisplay: Int {
        return likesCount ?? 0
    }
    
    // Convenience initializer to create a copy with updated likes
    func withUpdatedLikes(likes: [String], likesCount: Int) -> Suggestion {
        return Suggestion(
            id: self.id,
            userId: self.userId,
            userDetails: self.userDetails,
            message: self.message,
            placeId: self.placeId,
            placeDetails: self.placeDetails,
            imageUrl: self.imageUrl,
            mentionedPlaces: self.mentionedPlaces,
            commentsCount: self.commentsCount,
            likes: likes,
            likesCount: likesCount,
            createdAt: self.createdAt,
            updatedAt: self.updatedAt,
            expiresAt: self.expiresAt
        )
    }
    
    // Manual initializer
    init(id: String, userId: String, userDetails: User?, message: String, placeId: String?, placeDetails: Place?, imageUrl: String?, mentionedPlaces: [PlaceMention]?, commentsCount: Int?, likes: [String]?, likesCount: Int?, createdAt: Date, updatedAt: Date, expiresAt: Date) {
        self.id = id
        self.userId = userId
        self.userDetails = userDetails
        self.message = message
        self.placeId = placeId
        self.placeDetails = placeDetails
        self.imageUrl = imageUrl
        self.mentionedPlaces = mentionedPlaces
        self.commentsCount = commentsCount
        self.likes = likes
        self.likesCount = likesCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
    }
}

// Response types for API
struct SuggestionsResponse: Codable {
    let success: Bool
    let data: [Suggestion]
}

// Place mention in suggestion text
struct PlaceMention: Codable {
    let placeId: String
    let name: String
    let startIndex: Int
    let endIndex: Int
}

struct SuggestionResponse: Codable {
    let success: Bool
    let data: Suggestion
    let message: String?
}