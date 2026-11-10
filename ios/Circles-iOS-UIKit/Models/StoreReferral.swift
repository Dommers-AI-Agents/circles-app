import Foundation

/// Bring a friend (2026-11-09; server: services/storeReferrals.js).
/// Customer side: the store's offer and this person's own invite link.
struct StoreReferral: Codable, Equatable {
    let enabled: Bool
    let referrerPoints: Int
    let friendPoints: Int
    let inviteUrl: String?
}

/// Owner side: the setting
struct StoreReferralSettings: Codable, Equatable {
    var enabled: Bool
    var referrerPoints: Int
    var friendPoints: Int

    static let off = StoreReferralSettings(enabled: false, referrerPoints: 50, friendPoints: 25)

    var asBody: [String: Any] { ["enabled": enabled, "referrerPoints": referrerPoints, "friendPoints": friendPoints] }
}

struct StoreReferralStats: Codable, Equatable {
    let friendsBrought: Int
    let thisMonth: Int
    let pointsPaid: Int
}

struct StoreReferralsData: Codable {
    let settings: StoreReferralSettings
    let stats: StoreReferralStats?
}
