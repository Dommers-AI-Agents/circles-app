import Foundation

/// Coupons: what a scan, the store page, the ticket and the owner's list
/// say. Pure.
enum StoreCouponCopy {

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// "through Dec 5"
    static func throughLine(_ expiresAt: String?) -> String? {
        ISO8601.date(expiresAt).map { "through \(day.string(from: $0))" }
    }

    /// "Ends Dec 5" / "Ended Nov 1"
    static func endsLine(_ expiresAt: String?, now: Date = Date()) -> String? {
        guard let date = ISO8601.date(expiresAt) else { return nil }
        return date < now ? "Ended \(day.string(from: date))" : "Ends \(day.string(from: date))"
    }

    // MARK: The scan

    /// After a window scan: one line for the alert, by what happened
    static func scanLine(_ result: ScanCouponResult, storeName: String) -> String? {
        let title = result.coupon?.title ?? result.claim?.title
        switch result.status {
        case "claimed":
            guard let title else { return nil }
            var line = "Your coupon is saved: \(title)."
            if let through = throughLine(result.coupon?.expiresAt ?? result.claim?.expiresAt) { line += " Good \(through)." }
            line += " It's in \(storeName)'s rewards and on its Wallet card. Scan the register code when you're there and show the ticket."
            if let code = result.coupon?.onlineCode ?? result.claim?.onlineCode { line += " Ordering online? Use code \(code)." }
            return line
        case "already":
            guard let title else { return nil }
            switch result.claim?.status {
            case "used": return "You've already used this coupon (\(title))."
            case "expired": return "That coupon (\(title)) has ended."
            default: return "You already have this coupon: \(title). It's in \(storeName)'s rewards."
            }
        case "expired": return title.map { "That coupon (\($0)) has ended." } ?? "That coupon has ended."
        case "full": return title.map { "That coupon (\($0)) has all been claimed." } ?? "That coupon has all been claimed."
        case "paused": return title.map { "\(storeName) has paused that coupon (\($0))." } ?? "\(storeName) has paused that coupon."
        default: return nil
        }
    }

    /// After a register scan opened the coupon's ticket
    static func ticketLine(_ result: ScanCouponResult) -> String? {
        guard result.status == "ticket", let title = result.claim?.title ?? result.voucher?.offerTitle else { return nil }
        return "Your coupon is open: \(title). Show the ticket at the counter."
    }

    static func ticketButton(_ result: ScanCouponResult) -> String? {
        result.status == "ticket" ? "Show my coupon" : nil
    }

    // MARK: The customer's coupons

    /// The row under a coupon: fine print, the end date, the online code
    static func claimDetail(_ coupon: StoreCoupon, now: Date = Date()) -> String {
        var parts: [String] = []
        if let detail = coupon.detail, !detail.isEmpty { parts.append(detail) }
        switch coupon.status {
        case "used":
            parts.append(ISO8601.date(coupon.usedAt).map { "Used \(day.string(from: $0))" } ?? "Used")
        case "ticket":
            parts.append("Ticket open · show it at the counter")
        default:
            if let ends = endsLine(coupon.expiresAt, now: now) { parts.append(ends) }
        }
        if coupon.isOpen, let code = coupon.onlineCode, !code.isEmpty { parts.append("Online code \(code)") }
        return parts.joined(separator: " · ")
    }

    /// The button on an open coupon
    static func useButton(_ coupon: StoreCoupon) -> String? {
        switch coupon.status {
        case "claimed": return "Use now"
        case "ticket": return "Show ticket"
        default: return nil
        }
    }

    static let useExplainer = "Opens a 15-minute ticket to show at the counter. Staff tap Given on it. If it isn't used in time, the coupon stays yours."

    /// The ticket's words when it is a coupon, not points
    static func ticketExpiredLine(storeName: String) -> String {
        "This coupon wasn\u{2019}t marked as given, so it\u{2019}s still yours at \(storeName). Open it again when you\u{2019}re at the counter."
    }

    static func onlineCodeLine(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return "Ordering online? Use code \(code)."
    }

    // MARK: Owner

    static let rowTitle = "Coupons"
    static let rowSubtitle = "A QR for flyers and mailers that saves the coupon in the app, so it can't be forgotten at home"

    static func summary(_ coupons: [VenueCoupon]) -> String {
        let live = coupons.filter { $0.state == "live" }
        guard !coupons.isEmpty else { return rowSubtitle }
        let used = coupons.reduce(0) { $0 + ($1.counts?.redemptions ?? 0) }
        let claimed = coupons.reduce(0) { $0 + ($1.counts?.claims ?? 0) }
        return "\(live.count) live · \(claimed) claimed · \(used) used"
    }

    /// Under each coupon on the owner's list
    static func ownerLine(_ coupon: VenueCoupon, now: Date = Date()) -> String {
        var parts: [String] = []
        switch coupon.state {
        case "paused": parts.append("Paused")
        case "full": parts.append("All claimed")
        case "ended": parts.append(endsLine(coupon.expiresAt, now: now) ?? "Ended")
        default: parts.append(endsLine(coupon.expiresAt, now: now) ?? "Live")
        }
        if let campaign = coupon.campaign, !campaign.isEmpty { parts.append(campaign) }
        if let counts = coupon.counts {
            parts.append("\(counts.scans) scan\(counts.scans == 1 ? "" : "s") · \(counts.claims) claimed · \(counts.redemptions) used")
        }
        return parts.joined(separator: " · ")
    }

    /// The owner's numbers for one coupon, as tiles
    static func tiles(_ coupon: VenueCoupon) -> [(title: String, value: String)] {
        let c = coupon.counts ?? VenueCouponCounts(scans: 0, claims: 0, tickets: 0, redemptions: 0, newCustomers: 0)
        var rows = [(title: "Scans", value: "\(c.scans)"), (title: "Claimed", value: "\(c.claims)"), (title: "Used", value: "\(c.redemptions)"), (title: "New customers", value: "\(c.newCustomers)")]
        if let max = coupon.maxClaims { rows[1].value = "\(c.claims) / \(max)" }
        return rows
    }

    static let explanation = "Print the QR on a flyer, mailer, bag or table card. A scan saves your store, signs the customer in and puts the coupon on their Wallet card and in Store Rewards. When they scan your register code, the coupon becomes a 15-minute ticket staff tap Given on. One claim per person. Business only."

    static let qrCaption = "Customers scan this to claim the coupon in FavCircles. Put it on the flyer, the mailer, the bag."

    /// The one-bubble link's title when the owner shares it
    static func shareTitle(storeName: String, coupon: VenueCoupon) -> String {
        "\(coupon.title) at \(storeName) — scan to claim it"
    }

    static let empty = "No coupons yet. Add one, print its QR on your next flyer, and see who kept it."
    static let noneToPick = "Add a coupon under Coupons in Manage Store first, then pick it here."
}
