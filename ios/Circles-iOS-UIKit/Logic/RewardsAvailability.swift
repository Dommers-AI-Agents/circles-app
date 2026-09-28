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
                .map { Offer(title: $0.title, pointsCost: $0.pointsCost) }
        ))
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

    /// The check-in confirmation's line about rewards.
    static func checkInNudge(_ details: Details) -> String {
        let earn = details.earnRate.map { $0 > 0 ? " gives \($0) \($0 == 1 ? "point" : "points") per visit" : " has rewards" } ?? " has rewards"
        return "\(details.venueName)\(earn). Scan the QR code at the register to collect them."
    }
}
