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
    /// "save" (a window code's save bonus, 2026-11-01; "signup" before) or
    /// "visit" (a register code's points); signupBonusPoints = what it awards
    let scanPointsKind: String?
    let earnRate: Int?
    let offers: [ClipOffer]?
    let firstReward: ClipOffer?
    /// The store's cover photo, shown full screen behind the clip
    let coverUrl: String?
    /// Where the store is, for Apple's at-the-store check on register codes
    let location: ClipLocation?
    /// The store's waitlist, while it's on: the clip offers "Join the line" (2026-11-09)
    let waitlist: ClipWaitlist?

    var isGeneric: Bool { generic == true }
    /// A store's window code: the clip saves the store as it signs them in
    var isStoreWindow: Bool { !isGeneric && kind != "register" }
    /// Points that code pays: a window code's save bonus or a register
    /// code's visit, only where the store's rewards are live
    var pointsHere: Int { loyaltyLive == true ? signupBonusPoints : 0 }
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
    /// An instant sign-up: the email isn't confirmed yet (the app asks later)
    let emailUnverified: Bool?

    var isEmailUnverified: Bool { emailUnverified == true || user.emailUnverified == true }
}

struct ClipUser: Decodable {
    let id: String
    let displayName: String?
    let email: String?
    let emailUnverified: Bool?

    // The auth endpoints serialize the user with Mongo-style "_id"
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case displayName
        case email
        case emailUnverified
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
    /// Window code (2026-11-01): the clip asked the server to save the store
    let saved: Bool?
    /// The save couldn't be made now; the app's own save flow finishes it
    let savePending: Bool?
    let savedPlace: SavedPlace?
    let loyaltyLive: Bool?
    let offers: [ClipOffer]?

    struct SavedPlace: Decodable {
        let placeId: String?
        let circleId: String?
    }

    var isOnTheirMap: Bool { saved == true || alreadySaved == true }
}

struct ClipWaitlist: Decodable {
    let enabled: Bool
    let quoteMinutes: Int
}

/// The clip's spot in a store's line (the same shape the app decodes)
struct ClipWaitlistEntry: Decodable {
    let entryId: String
    let status: String
    let position: Int?
    let estimateMinutes: Int?
    let alreadyInLine: Bool?
}

struct ClipWaitlistResponse: Decodable {
    let success: Bool
    let data: ClipWaitlistEntry
}

struct ScanAward: Decodable {
    let type: String
    let points: Int
}

// Server error bodies come as {error: "..."} or {message: "..."}
struct ClipErrorBody: Decodable {
    let error: String?
    let message: String?
    let code: String?
}

struct ClipSimpleResponse: Decodable {
    let success: Bool
}

// MARK: - Scan Actions (/q/<code>, 2026-11-11)

/// What a Scan Action QR holds, as much as the clip needs (the app's
/// Models/ScanAction.swift has the whole shape)
struct ClipScanAction: Decodable {
    struct Creator: Decodable { let displayName: String }
    struct Place: Decodable {
        let globalPlaceId: String
        let name: String
        let address: String?
        let photoUrl: String?
        let alreadySaved: Bool?
    }
    struct Guide: Decodable { let title: String; let blurb: String? }
    struct Store: Decodable { let name: String? }

    let code: String
    let kind: String
    let title: String?
    let note: String?
    let expired: Bool?
    let creator: Creator?
    let guide: Guide?
    let store: Store?
    let places: [Place]?

    /// A place or a list the clip can save; guides and store setup need the app
    var isSaveable: Bool { kind == "place" || kind == "placeSet" }
}

struct ClipScanActionResponse: Decodable {
    let success: Bool
    let data: ClipScanAction
}

struct ClipScanSaveResult: Decodable {
    struct Row: Decodable { let globalPlaceId: String; let name: String?; let placeId: String?; let circleName: String? }
    let circleId: String?
    let saved: [Row]
    let alreadySaved: [Row]
    let failed: [Row]
}

struct ClipScanSaveResponse: Decodable {
    let success: Bool
    let data: ClipScanSaveResult
}
