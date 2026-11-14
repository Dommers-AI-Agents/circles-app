import Foundation

/// Coupons (2026-11-14; server: services/storeCoupons.js). A store's flyer
/// or mailer coupon: its QR is the window link plus ?c=<coupon>, so a scan
/// claims it for the account and it lives here instead of on the fridge.

/// The coupon as the store wrote it (on a scan, a preview)
struct StoreCouponOffer: Codable, Equatable {
    let couponId: String
    let title: String
    let detail: String?
    let onlineCode: String?
    let expiresAt: String?
}

/// One person's claim of a coupon: what it is and where it stands
struct StoreCoupon: Codable, Equatable {
    let claimId: String
    let venueId: String
    let venueName: String?
    let couponId: String
    let title: String
    let detail: String?
    let onlineCode: String?
    let campaign: String?
    let expiresAt: String?
    let claimedAt: String?
    /// "claimed" | "ticket" (a counter ticket is open) | "used" | "expired"
    var status: String
    /// The open ticket's id while status is "ticket"
    let voucherId: String?
    let usedAt: String?

    var isOpen: Bool { status == "claimed" || status == "ticket" }
    var expiryDate: Date? { ISO8601.date(expiresAt) }
}

/// What a scan said about the coupon on its link
struct ScanCouponResult: Codable, Equatable {
    /// claimed | already | expired | full | paused | not_found | ticket
    let status: String
    let coupon: StoreCouponOffer?
    let claim: StoreCoupon?
    /// The register scan opened the coupon's counter ticket
    let voucher: RewardVoucher?
}

/// "Use now": the ticket the coupon became
struct StoreCouponTicket: Codable {
    let claim: StoreCoupon
    let voucher: RewardVoucher
    let already: Bool?
}

// MARK: - Owner side

struct VenueCouponCounts: Codable, Equatable {
    let scans: Int
    let claims: Int
    let tickets: Int
    let redemptions: Int
    let newCustomers: Int
}

/// One of the store's coupons, with its link and how it is doing
struct VenueCoupon: Codable, Equatable {
    let couponId: String
    var title: String
    var detail: String?
    var onlineCode: String?
    var campaign: String?
    var expiresAt: String
    var maxClaims: Int?
    var active: Bool
    let createdAt: String?
    let url: String?
    let counts: VenueCouponCounts?
    /// live | paused | ended | full
    let state: String?

    var expiryDate: Date? { ISO8601.date(expiresAt) }
}

struct VenueCouponsData: Codable {
    let coupons: [VenueCoupon]
}

struct VenueCouponSaved: Codable {
    let coupon: VenueCoupon?
    let coupons: [VenueCoupon]
}

/// The owner's draft of a coupon, checked before it goes to the server. Pure.
struct VenueCouponEdit: Equatable {
    var title = ""
    var detail = ""
    var onlineCode = ""
    var campaign = ""
    var expiresAt: Date
    var maxClaimsText = ""
    var isActive = true

    static let maxTitle = 60
    static let maxDetail = 200

    init(expiresAt: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()) {
        self.expiresAt = expiresAt
    }

    init(coupon: VenueCoupon) {
        title = coupon.title
        detail = coupon.detail ?? ""
        onlineCode = coupon.onlineCode ?? ""
        campaign = coupon.campaign ?? ""
        expiresAt = coupon.expiryDate ?? Date()
        maxClaimsText = coupon.maxClaims.map(String.init) ?? ""
        isActive = coupon.active
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var maxClaims: Int? {
        let text = maxClaimsText.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : Int(text)
    }

    /// The first thing wrong, in the owner's words; nil when it can go
    func problem(now: Date = Date()) -> String? {
        if trimmedTitle.isEmpty { return "Say what the coupon gives, like \u{201C}20% off any pickup order\u{201D}." }
        if trimmedTitle.count > Self.maxTitle { return "Keep the coupon to \(Self.maxTitle) characters." }
        if detail.trimmingCharacters(in: .whitespacesAndNewlines).count > Self.maxDetail { return "Keep the fine print to \(Self.maxDetail) characters." }
        let code = onlineCode.trimmingCharacters(in: .whitespaces)
        if !code.isEmpty, code.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]*$", options: .regularExpression) == nil {
            return "An online code is letters and numbers, like TGOSTVQC."
        }
        if expiresAt <= now { return "Pick a day that hasn\u{2019}t passed." }
        if !maxClaimsText.trimmingCharacters(in: .whitespaces).isEmpty, maxClaims == nil || maxClaims! < 1 {
            return "How many may claim it: a whole number, or leave it blank."
        }
        return nil
    }

    /// The coupon runs through the end of the chosen day, in the owner's own time
    var expiresAtIso: String {
        let end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: expiresAt) ?? expiresAt
        return ISO8601.string(end)
    }

    var asBody: [String: Any] {
        var body: [String: Any] = [
            "title": trimmedTitle,
            "detail": detail.trimmingCharacters(in: .whitespacesAndNewlines),
            "onlineCode": onlineCode.trimmingCharacters(in: .whitespaces).uppercased(),
            "campaign": campaign.trimmingCharacters(in: .whitespacesAndNewlines),
            "expiresAt": expiresAtIso,
            "active": isActive
        ]
        body["maxClaims"] = maxClaims.map { $0 as Any } ?? NSNull()
        return body
    }
}

/// ISO-8601 with or without fractional seconds, the way the server writes dates
enum ISO8601 {
    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
