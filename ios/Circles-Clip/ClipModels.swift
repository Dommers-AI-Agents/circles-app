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
    /// The coupon on the link (?c=), when the store still has it (2026-11-14)
    var coupon: ClipCoupon? = nil
    /// The screens after Open at a store's window code (2026-11-26): the
    /// server fills them from the store and its owner's choices. Absent
    /// (older server, switch off): the clip keeps today's screens.
    var experience: ClipExperience? = nil

    var isGeneric: Bool { generic == true }
    /// A store's window code: the clip saves the store as it signs them in
    var isStoreWindow: Bool { !isGeneric && kind != "register" }
    /// Points that code pays: a window code's save bonus or a register
    /// code's visit, only where the store's rewards are live
    var pointsHere: Int { loyaltyLive == true ? signupBonusPoints : 0 }
    var favCoinBonus: Int { signupBonusCoins ?? 50 }
    /// The Welcome → sign-in → connected screens apply: a store's window
    /// code with the server's experience and no flyer coupon (that flow
    /// leads with the coupon)
    var storeExperience: ClipExperience? {
        guard isStoreWindow, coupon?.available == false || coupon == nil else { return nil }
        return experience
    }
}

/// What the screens after Open say at this store (services/clipExperience.js)
struct ClipExperience: Decodable {
    struct Row: Decodable {
        /// rewards | menu | specials | events | announcements
        let kind: String
        let title: String
        let detail: String
        let url: String?
    }
    struct Welcome: Decodable {
        let title: String
        let line: String
        let ratingLine: String?
        let photoUrl: String?
        let rows: [Row]
        let button: String
    }
    struct Connect: Decodable {
        let hook: [String]
        let photoUrl: String?
        let about: String
        let alerts: String
        let pointsLine: String?
    }
    struct Done: Decodable {
        let hook: [String]
        let line: String
        let showRewards: Bool
        let showWallet: Bool
    }
    let shortName: String
    let welcome: Welcome
    let connect: Connect
    let done: Done
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
    /// The account was made by this sign-in: email-instant and email-code
    /// answer `newAccount`, Sign in with Apple answers `isNewUser`
    let newAccount: Bool?
    let isNewUser: Bool?

    var isEmailUnverified: Bool { emailUnverified == true || user.emailUnverified == true }
    /// A brand-new account: the steps after the save are for them (2026-11-24)
    var isNewAccount: Bool { newAccount == true || isNewUser == true }
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
    /// The flyer's coupon: claimed on this scan, or why not (2026-11-14)
    var coupon: ClipCouponResult? = nil

    struct SavedPlace: Decodable {
        let placeId: String?
        let circleId: String?
    }

    var isOnTheirMap: Bool { saved == true || alreadySaved == true }
}

/// A store's flyer coupon as the link names it
struct ClipCoupon: Decodable {
    let couponId: String?
    let title: String
    let detail: String?
    let onlineCode: String?
    let expiresAt: String?
    /// false once it has ended, been paused or all been claimed
    var available: Bool? = nil
}

struct ClipCouponResult: Decodable {
    /// claimed | already | expired | full | paused | not_found
    let status: String
    let coupon: ClipCoupon?
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

// MARK: - The steps after the save (2026-11-24)

/// A person to follow, as users/contacts/discover?type=welcome shapes them
/// (the app's User, trimmed to what the clip shows)
struct ClipPerson: Decodable {
    let id: String
    let displayName: String
    let profilePicture: String?
    let placesCount: Int?
    let location: String?
    /// "Also loves Pasta & Provisions", "Near you", "Followed for you"
    let suggestionReason: String?
    let isFollowing: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, displayName, profilePicture, placesCount, location, suggestionReason, isFollowing
        case mongoId = "_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try c.decodeIfPresent(String.self, forKey: .id) ?? c.decodeIfPresent(String.self, forKey: .mongoId) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: decoder.codingPath, debugDescription: "no id"))
        }
        self.id = id
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? "Someone"
        profilePicture = try c.decodeIfPresent(String.self, forKey: .profilePicture)
        placesCount = try c.decodeIfPresent(Int.self, forKey: .placesCount)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        suggestionReason = try c.decodeIfPresent(String.self, forKey: .suggestionReason)
        isFollowing = try c.decodeIfPresent(Bool.self, forKey: .isFollowing)
    }

    var initials: String {
        displayName.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    /// "Also loves Pasta & Provisions · 128 places"
    var detailLine: String {
        var parts: [String] = []
        if let suggestionReason, !suggestionReason.isEmpty { parts.append(suggestionReason) }
        if let placesCount, placesCount > 0 { parts.append("\(placesCount) place\(placesCount == 1 ? "" : "s")") }
        if parts.isEmpty, let location, !location.isEmpty { parts.append(location) }
        return parts.isEmpty ? "Just getting started" : parts.joined(separator: " · ")
    }
}

struct ClipPeopleResponse: Decodable {
    let success: Bool
    let users: [ClipPerson]
}

/// POST users/:id/follow: a private profile answers with a request
struct ClipFollowResponse: Decodable {
    let success: Bool
    let requested: Bool?
}

/// POST clip/favorites: what the core save did with each pick
struct ClipFavoritesResult: Decodable {
    struct Row: Decodable { let placeId: String?; let name: String }
    struct Failed: Decodable { let name: String; let reason: String? }
    let saved: [Row]
    let alreadySaved: [Row]
    let failed: [Failed]
    /// FavCoins the saves earned (the first place ever, when the store wasn't it)
    let coins: Int?
}

struct ClipFavoritesResponse: Decodable {
    let success: Bool
    let data: ClipFavoritesResult
}
