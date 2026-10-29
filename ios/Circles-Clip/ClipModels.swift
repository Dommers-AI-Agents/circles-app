import Foundation

// Trimmed response models for the three backend calls the clip makes.
// Mirrors the API shapes used by the full app (AuthResponse in AuthService.swift)
// but decodes only what the clip renders.

struct VenuePreviewResponse: Decodable {
    let success: Bool
    let data: VenuePreview
}

struct VenuePreview: Decodable {
    let venueName: String
    let placeName: String?
    let placeAddress: String?
    let category: String?
    let kind: String? // "window" | "register"
    let signupBonusPoints: Int
    let signupBonusCoins: Int? // generic joins reward FavCoins instead of store points
    let generic: Bool? // true = "Join FavCircles" code, no store attached
    /// The store's own terms (2026-10-29): points per visit and the first
    /// reward on its menu, only while its loyalty program is live
    let loyaltyLive: Bool?
    let earnRate: Int?
    let offers: [ClipOffer]?
    let firstReward: ClipOffer?

    var isGeneric: Bool { generic == true }
    var favCoinBonus: Int { signupBonusCoins ?? 50 }
}

struct ClipAuthResponse: Decodable {
    let success: Bool
    let token: String
    let refreshToken: String?
    let expiresIn: Int?
    let user: ClipUser
}

struct ClipUser: Decodable {
    let id: String
    let displayName: String?
    let email: String?

    // The auth endpoints serialize the user with Mongo-style "_id"
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case displayName
        case email
    }
}

struct ScanResponse: Decodable {
    let success: Bool
    let data: ScanResult
}

struct ClipOffer: Decodable {
    let title: String
    let pointsCost: Int
}

struct ScanResult: Decodable {
    let kind: String?
    let awarded: ScanAward?
    let balance: Int?
    let venueBalance: Int?
    /// "75 more points for a free coffee · about 3 more visits" (server-made)
    let nextRewardLine: String?
}

struct ScanAward: Decodable {
    let type: String
    let points: Int
}

// Server error bodies come as {error: "..."} or {message: "..."}
struct ClipErrorBody: Decodable {
    let error: String?
    let message: String?
}
