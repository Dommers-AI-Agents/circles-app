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

struct ScanResult: Decodable {
    let kind: String?
    let awarded: ScanAward?
    let balance: Int?
    let venueBalance: Int?
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
