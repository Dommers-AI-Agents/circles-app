import Foundation

/// Wording and tiles for the owner's Insights page. Pure — no UIKit — so the
/// rules (what a score reads as, when a trend is "steady", which customers
/// count as regulars) are table-tested.
enum VenueInsightsCopy {

    enum Range: String, CaseIterable {
        case days30 = "30d"
        case days90 = "90d"
        case months12 = "12m"

        var title: String {
            switch self {
            case .days30: return "30 days"
            case .days90: return "90 days"
            case .months12: return "12 months"
            }
        }
    }

    // MARK: Score

    /// "8.4 / 10", or "No ratings yet"
    static func scoreLine(average: Double?) -> String {
        guard let average else { return "No ratings yet" }
        let text = average.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(average)) : String(format: "%.1f", average)
        return "\(text) / 10"
    }

    /// "12 ratings · 9 recommend it (75%)"; "1 rating · recommends it";
    /// nothing rated: how the score comes to be
    static func scoreCaption(ratings: Int, recommend: Int, recommendPct: Int?) -> String {
        guard ratings > 0 else { return "Customers who save your store rate it 0–10 in FavCircles. Their average is your score." }
        let count = ratings == 1 ? "1 rating" : "\(ratings) ratings"
        guard recommend > 0 else { return count }
        let pct = recommendPct.map { " (\($0)%)" } ?? ""
        return "\(count) · \(recommend) recommend it\(pct)"
    }

    /// Against the 30 days before; nil when either side has no ratings
    static func trendLine(_ trend: Double?) -> String? {
        guard let trend else { return nil }
        if abs(trend) < 0.05 { return "Steady vs. the 30 days before" }
        let sign = trend > 0 ? "+" : "−"
        return "\(sign)\(String(format: "%.1f", abs(trend))) vs. the 30 days before"
    }

    /// "Google 4.6★ · 212 reviews" — shown beside the score; both stay
    static func googleLine(rating: Double?, total: Int) -> String? {
        guard let rating else { return nil }
        let reviews = total == 1 ? "1 review" : "\(total) reviews"
        return total > 0 ? "Google \(String(format: "%.1f", rating))★ · \(reviews)" : "Google \(String(format: "%.1f", rating))★"
    }

    // MARK: Customers

    static func customerTiles(_ c: VenueInsightsData.Customers, range: Range) -> [VenueAdminCopy.StatTile] {
        let period = "in the last \(range.title)"
        return [
            .init(title: "New customers", value: c.newCustomers, caption: "First purchase here \(period)", monthNote: nil),
            .init(title: "Came back", value: c.returningCustomers, caption: "Bought here before, and again \(period)", monthNote: nil),
            .init(title: "Regulars", value: c.regulars, caption: "3 or more purchases, all time", monthNote: nil),
            .init(title: "Haven't been back", value: c.lapsed, caption: "No purchase in 30 days", monthNote: nil)
        ]
    }

    /// "42% of your customers have bought here more than once"
    static func repeatLine(pct: Int?, total: Int) -> String {
        guard let pct, total > 0 else { return "Repeat rate shows once a few customers have scanned at the register." }
        return "\(pct)% of your \(total == 1 ? "customer has" : "\(total) customers have") bought here more than once"
    }

    /// "3 new customers came through a friend's invite"; nil when none
    static func referredLine(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return count == 1 ? "1 new customer came through a friend's invite" : "\(count) new customers came through a friend's invite"
    }

    static func visitsLine(visits: Int, visitors: Int, range: Range) -> String {
        guard visits > 0 else { return "No register scans in the last \(range.title)" }
        let people = visitors == 1 ? "1 person" : "\(visitors) people"
        return "\(visits) purchase\(visits == 1 ? "" : "s") by \(people) in the last \(range.title)"
    }

    // MARK: Offers and comments

    static func offerLine(_ offer: VenueInsightsData.Offer) -> String {
        "\(offer.title) · \(offer.redemptions) redeemed"
    }

    static func offersEmpty(range: Range) -> String {
        "No rewards redeemed in the last \(range.title). Offers customers can reach in a few visits get redeemed most."
    }

    static func awaitingLine(count: Int) -> String {
        switch count {
        case 0: return "Every review has a reply from you"
        case 1: return "1 review is waiting for a reply"
        default: return "\(count) reviews are waiting for a reply"
        }
    }

    static func commentsLine(inPeriod: Int, total: Int, range: Range) -> String {
        guard total > 0 else { return "No reviews on FavCircles yet. After a reward, customers are asked to rate your store and write one." }
        return "\(inPeriod) new in the last \(range.title) · \(total) in all"
    }

    /// The page's stale banner while the server recomputes (never blocks the page)
    static let staleNote = "Updating…"

    // MARK: Coupons (2026-11-14)

    /// "Nov mailer · 20% off any pickup order"
    static func campaignTitle(_ c: VenueInsightsData.Campaign) -> String {
        [c.campaign, c.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "84 scans → 31 claimed → 12 used · 9 new customers · 14 came in"
    static func campaignLine(_ c: VenueInsightsData.Campaign) -> String {
        var line = "\(c.scans) scan\(c.scans == 1 ? "" : "s") → \(c.claims) claimed → \(c.used) used"
        if c.newCustomers > 0 { line += " · \(c.newCustomers) new customer\(c.newCustomers == 1 ? "" : "s")" }
        if c.cameIn > 0 { line += " · \(c.cameIn) came in after claiming" }
        if c.state == "ended" { line += " · ended" } else if c.state == "paused" { line += " · paused" }
        return line
    }

    static let campaignsEmpty = "No coupons yet. Add one under Coupons in Manage Store and put its QR on your next flyer."

    // MARK: Posts (2026-11-14)

    /// "Sent to 212 · 38 came in since"
    static func postLine(_ p: VenueInsightsData.Post) -> String {
        let kind = p.kind == "event" ? "Event" : (p.kind == "offer" ? "Reward" : "Post")
        var line = "\(kind) · sent to \(p.sentTo) follower\(p.sentTo == 1 ? "" : "s")"
        if p.cameIn > 0 { line += " · \(p.cameIn) came in since" }
        return line
    }

    static let postsEmpty = "Nothing posted yet. A new offer, announcement or event goes to everyone who turned on your store's alerts, and you'll see here how many came in after."
}
