import Foundation

/// Bring a friend (2026-11-09; server: services/storeReferrals.js).
/// Customer side: the store's offer and this person's own invite link.
struct StoreReferral: Codable, Equatable {
    let enabled: Bool
    let referrerPoints: Int
    let friendPoints: Int
    let inviteUrl: String?
    /// A coupon the friend gets on the link too (2026-11-14)
    var friendCoupon: StoreCouponOffer? = nil
}

/// Owner side: the setting
struct StoreReferralSettings: Codable, Equatable {
    var enabled: Bool
    var referrerPoints: Int
    var friendPoints: Int
    /// One of the store's coupons for the friend, on the invite link (2026-11-14)
    var couponId: String? = nil

    static let off = StoreReferralSettings(enabled: false, referrerPoints: 50, friendPoints: 25)

    var asBody: [String: Any] { ["enabled": enabled, "referrerPoints": referrerPoints, "friendPoints": friendPoints, "couponId": couponId ?? NSNull()] }
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
