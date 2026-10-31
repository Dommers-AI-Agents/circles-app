import Foundation

// Trimmed response models for the backend calls the clip makes.
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
    /// "signup" (a window code's one-time bonus) or "visit" (a register
    /// code's points for this visit); with signupBonusPoints = what it awards
    let scanPointsKind: String?
    let earnRate: Int?
    let offers: [ClipOffer]?
    let firstReward: ClipOffer?
    /// The store's cover photo, shown full screen behind the clip
    let coverUrl: String?
    /// Where the store is, for Apple's at-the-store check on register codes
    let location: ClipLocation?

    var isGeneric: Bool { generic == true }
    var favCoinBonus: Int { signupBonusCoins ?? 50 }
}

/// Takes {latitude, longitude} or the venue record's {lat, lng}
struct ClipLocation: Decodable {
    let latitude: Double?
    let longitude: Double?

    private enum CodingKeys: String, CodingKey { case latitude, longitude, lat, lng }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? c.decodeIfPresent(Double.self, forKey: .lat)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? c.decodeIfPresent(Double.self, forKey: .lng)
    }
}

/// The scanned store as the scan returns it (the app's RewardVenue shape),
/// passed to the app so its first launch can open the store's page
struct ClipVenue: Codable {
    let venueId: String
    let venueName: String
    let placeName: String?
    let placeAddress: String?
    let category: String?
    let googlePlaceId: String?
    let globalPlaceId: String?
    let location: ClipCoordinate?
}

struct ClipCoordinate: Codable {
    let lat: Double
    let lng: Double
}

struct EmailCodeStartResponse: Decodable {
    let success: Bool
    /// No account with this email yet: the code step also asks their name
    let newAccount: Bool?
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

struct ClipOffer: Codable {
    let title: String
    let pointsCost: Int
}

struct ScanResult: Decodable {
    let kind: String?
    let venue: ClipVenue?
    let alreadySaved: Bool?
    let awarded: ScanAward?
    let balance: Int?
    let venueBalance: Int?
    /// "75 more points for a free coffee · about 3 more visits" (server-made)
    let nextRewardLine: String?
    /// Apple's location check said the phone wasn't at the store: no visit points
    let notAtStore: Bool?
    let alreadyEarnedToday: Bool?
    let earnRate: Int?
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

struct ClipSimpleResponse: Decodable {
    let success: Bool
}
