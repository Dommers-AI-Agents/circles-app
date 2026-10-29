import Foundation

/// Whether a customer can earn store points at a place, and what the "Get
/// Rewards" page tells them. One rule for the place page button, the page
/// itself and the check-in nudge.
enum RewardsAvailability: Equatable {
    /// No rewards here — or none for this person (the store's own team).
    case none
    case earn(Details)

    struct Details: Equatable {
        let venueName: String
        /// Points one register scan awards.
        let earnRate: Int?
        /// Points this person already holds at this store.
        let venueBalance: Int
        let offers: [Offer]
        /// The store's current posts (specials, events), newest first
        var announcements: [Announcement] = []
    }

    struct Announcement: Equatable {
        let title: String
        let message: String
    }

    /// The reward a customer is working toward, for the progress card on
    /// Get Rewards (replaced "type a code", Wes 2026-10-29: stores only
    /// scan). The cheapest offer still out of reach; or, once something is
    /// affordable, the best one they can take right now.
    struct NextReward: Equatable {
        let title: String
        let pointsCost: Int
        /// Points still needed; 0 when they can redeem now
        let remaining: Int
        /// Register scans still needed at the store's earn rate; nil when the rate is unknown
        let visitsLeft: Int?
        /// 0…1 toward the reward
        let fraction: Float
        var canRedeem: Bool { remaining == 0 }
    }

    struct Offer: Equatable {
        let title: String
        let pointsCost: Int
    }

    /// - Rewards exist only where a store is enrolled, and only while scans
    ///   actually award points (`rewardsLive`; a server that predates the
    ///   field is taken as live, as the page did before it).
    /// - The store's own team never sees "Get Rewards": they manage the store.
    init(_ data: PlaceVenueData?) {
        guard let data, let venue = data.venue,
              data.rewardsLive != false,
              data.isOwner != true else {
            self = .none
            return
        }
        self = .earn(Details(
            venueName: venue.venueName,
            earnRate: venue.earnRate,
            venueBalance: data.venueBalance ?? 0,
            offers: (data.offers ?? [])
                .filter { $0.active != false }
                .map { Offer(title: $0.title, pointsCost: $0.pointsCost) },
            announcements: (data.announcements ?? [])
                .filter { !$0.isExpired }
                .map { Announcement(title: $0.title, message: $0.message) }
        ))
    }

    /// The store card's header line for a venue. Rewards copy ("Rewards at",
    /// the earn line) appears only while scans award points; an enrolled
    /// store with no owner yet, or a lapsed one, is just the store by name.
    struct StoreCardHeader: Equatable {
        let title: String
        let showsEarnLine: Bool
    }

    static func storeCardHeader(venueName: String, isOwner: Bool, rewardsLive: Bool) -> StoreCardHeader {
        if isOwner { return StoreCardHeader(title: "Your Store · \(venueName)", showsEarnLine: rewardsLive) }
        return StoreCardHeader(title: rewardsLive ? "Rewards at \(venueName)" : venueName, showsEarnLine: rewardsLive)
    }

    var details: Details? {
        if case .earn(let details) = self { return details }
        return nil
    }

    /// "Earn 10 points per visit" — nil when the server didn't say.
    static func earnLine(_ details: Details) -> String? {
        guard let rate = details.earnRate, rate > 0 else { return nil }
        return "Earn \(rate) \(rate == 1 ? "point" : "points") per visit"
    }

    /// "You have 30 points here" / "You don't have any points here yet".
    static func balanceLine(_ details: Details) -> String {
        switch details.venueBalance {
        case ...0: return "You don't have any points here yet"
        case 1: return "You have 1 point here"
        default: return "You have \(details.venueBalance) points here"
        }
    }

    static func nextReward(_ details: Details) -> NextReward? {
        let offers = details.offers.filter { $0.pointsCost > 0 }.sorted { $0.pointsCost < $1.pointsCost }
        guard !offers.isEmpty else { return nil }
        let balance = max(0, details.venueBalance)
        if let best = offers.last(where: { $0.pointsCost <= balance }) {
            return NextReward(title: best.title, pointsCost: best.pointsCost, remaining: 0, visitsLeft: 0, fraction: 1)
        }
        let next = offers[0]
        let remaining = next.pointsCost - balance
        let visits = details.earnRate.flatMap { $0 > 0 ? Int((Double(remaining) / Double($0)).rounded(.up)) : nil }
        return NextReward(title: next.title, pointsCost: next.pointsCost, remaining: remaining, visitsLeft: visits,
                          fraction: Float(balance) / Float(next.pointsCost))
    }

    /// "75 more points for a free drip coffee · about 3 more visits" /
    /// "You've got enough for a free drip coffee".
    static func nextRewardLine(_ reward: NextReward) -> String {
        if reward.canRedeem { return "You've got enough for \(article(reward.title)). Scan at the register to use it." }
        var line = "\(reward.remaining) more \(reward.remaining == 1 ? "point" : "points") for \(article(reward.title))"
        if let visits = reward.visitsLeft, visits > 0 { line += " · about \(visits) more \(visits == 1 ? "visit" : "visits")" }
        return line
    }

    /// "Free drip coffee" → "a free drip coffee"; titles that already start with a/an/the/your keep theirs.
    private static func article(_ title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return t }
        let lower = t.lowercased()
        if ["a ", "an ", "the ", "your ", "free!"].contains(where: { lower.hasPrefix($0) }) { return t }
        let vowel = "aeiou".contains(first.lowercased())
        return "\(vowel ? "an" : "a") \(t.prefix(1).lowercased() + t.dropFirst())"
    }

    /// The check-in confirmation's line about rewards.
    static func checkInNudge(_ details: Details) -> String {
        let earn = details.earnRate.map { $0 > 0 ? " gives \($0) \($0 == 1 ? "point" : "points") per visit" : " has rewards" } ?? " has rewards"
        return "\(details.venueName)\(earn). Scan the QR code at the register to collect them."
    }
}
