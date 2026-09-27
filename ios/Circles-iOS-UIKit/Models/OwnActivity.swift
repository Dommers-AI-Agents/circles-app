import Foundation

/// One row of the signed-in user's own history (Profile › Activity), as the
/// server presents it: `GET /api/users/me/activity`. Everything is optional
/// but the id, type and time, so a row this build doesn't fully understand
/// still lists rather than sinking the page.
struct OwnActivityItem: Decodable, Equatable {
    let id: String
    let type: String
    let category: String?
    let timestamp: Date
    let targetType: String?
    let targetId: String?
    let targetName: String?
    let circleName: String?
    let placeId: String?
    let globalPlaceId: String?
    let placeAddress: String?
    let thumbnailUrl: String?
    let message: String?
    let rating: Int?
    let companions: [String]
    let isPrivate: Bool
    let contentType: String?
    let recipientName: String?
    let mailStatus: String?
    let likeCount: Int?
    let commentCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, category, timestamp, targetType, targetId, targetName, circleName, placeId, globalPlaceId, placeAddress
        case thumbnailUrl, message, rating, companions, isPrivate, contentType, recipientName, mailStatus, likeCount, commentCount
    }

    init(id: String, type: String, category: String? = nil, timestamp: Date, targetType: String? = nil, targetId: String? = nil,
         targetName: String? = nil, circleName: String? = nil, placeId: String? = nil, globalPlaceId: String? = nil,
         placeAddress: String? = nil, thumbnailUrl: String? = nil, message: String? = nil, rating: Int? = nil,
         companions: [String] = [], isPrivate: Bool = false, contentType: String? = nil, recipientName: String? = nil,
         mailStatus: String? = nil, likeCount: Int? = nil, commentCount: Int? = nil) {
        self.id = id; self.type = type; self.category = category; self.timestamp = timestamp
        self.targetType = targetType; self.targetId = targetId; self.targetName = targetName; self.circleName = circleName
        self.placeId = placeId; self.globalPlaceId = globalPlaceId; self.placeAddress = placeAddress; self.thumbnailUrl = thumbnailUrl
        self.message = message; self.rating = rating; self.companions = companions; self.isPrivate = isPrivate
        self.contentType = contentType; self.recipientName = recipientName; self.mailStatus = mailStatus
        self.likeCount = likeCount; self.commentCount = commentCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "unknown"
        category = try c.decodeIfPresent(String.self, forKey: .category)
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? .distantPast
        targetType = try c.decodeIfPresent(String.self, forKey: .targetType)
        targetId = try c.decodeIfPresent(String.self, forKey: .targetId)
        targetName = try c.decodeIfPresent(String.self, forKey: .targetName)
        circleName = try c.decodeIfPresent(String.self, forKey: .circleName)
        placeId = try c.decodeIfPresent(String.self, forKey: .placeId)
        globalPlaceId = try c.decodeIfPresent(String.self, forKey: .globalPlaceId)
        placeAddress = try c.decodeIfPresent(String.self, forKey: .placeAddress)
        thumbnailUrl = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating)
        companions = try c.decodeIfPresent([String].self, forKey: .companions) ?? []
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType)
        recipientName = try c.decodeIfPresent(String.self, forKey: .recipientName)
        mailStatus = try c.decodeIfPresent(String.self, forKey: .mailStatus)
        likeCount = try c.decodeIfPresent(Int.self, forKey: .likeCount)
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount)
    }
}

struct OwnActivityPage: Decodable {
    let success: Bool
    let filter: String
    let items: [OwnActivityItem]
    let nextCursor: String?
    let hasMore: Bool
}

/// The month at a glance: `GET /api/users/me/activity/summary`.
struct OwnActivitySummary: Decodable, Equatable {
    struct Counts: Decodable, Equatable {
        let checkins: Int
        let places: Int
        let moments: Int
        let sent: Int
        let social: Int
        let postcards: Int
    }
    struct MostVisited: Decodable, Equatable {
        let name: String
        let count: Int
    }
    struct OnThisDay: Decodable, Equatable {
        let placeName: String?
        let placeId: String?
        let at: Date?
    }
    let month: String
    let counts: Counts
    let streakWeeks: Int
    let mostVisited: MostVisited?
    let privateCheckIns: Int
    let onThisDay: [OnThisDay]
}

struct OwnActivitySummaryResponse: Decodable {
    let success: Bool
    let summary: OwnActivitySummary
}
