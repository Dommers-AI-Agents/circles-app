import Foundation

/// What Google tells us a place serves and offers, as one line for the place
/// page's About card ("Brunch & dinner · Wine & beer · Dine-in · Takeout"),
/// and a warning when Google lists it as closed (Wes, 2026-10-29). Only
/// what's known to be true is listed; nothing is shown when nothing is known.
struct PlaceServes: Codable, Equatable {
    var breakfast: Bool?
    var brunch: Bool?
    var lunch: Bool?
    var dinner: Bool?
    var beer: Bool?
    var wine: Bool?
    var vegetarian: Bool?
}

enum PlaceGoodToKnow {

    struct Facts: Equatable {
        var serves: PlaceServes?
        var dineIn: Bool?
        var takeout: Bool?
        var delivery: Bool?
        var curbsidePickup: Bool?
        var reservable: Bool?
        var wheelchairAccessibleEntrance: Bool?
    }

    static func facts(_ place: Place) -> Facts {
        Facts(serves: place.serves, dineIn: place.dineIn, takeout: place.takeout, delivery: place.delivery,
              curbsidePickup: place.curbsidePickup, reservable: place.reservable,
              wheelchairAccessibleEntrance: place.wheelchairAccessibleEntrance)
    }

    /// The items, in reading order; empty when Google told us nothing.
    static func items(_ f: Facts) -> [String] {
        var out: [String] = []
        let s = f.serves
        let meals = [("Breakfast", s?.breakfast), ("Brunch", s?.brunch), ("Lunch", s?.lunch), ("Dinner", s?.dinner)]
            .filter { $0.1 == true }.map(\.0)
        if let phrase = naturalList(meals) { out.append(phrase) }
        let drinks = [("Wine", s?.wine), ("Beer", s?.beer)].filter { $0.1 == true }.map(\.0)
        if let phrase = naturalList(drinks) { out.append(phrase) }
        if s?.vegetarian == true { out.append("Vegetarian options") }
        if f.dineIn == true { out.append("Dine-in") }
        if f.takeout == true { out.append("Takeout") }
        if f.delivery == true { out.append("Delivery") }
        if f.curbsidePickup == true { out.append("Curbside pickup") }
        if f.reservable == true { out.append("Takes reservations") }
        if f.wheelchairAccessibleEntrance == true { out.append("Wheelchair-accessible entrance") }
        return out
    }

    /// "Brunch & dinner · Wine & beer · Dine-in", or nil.
    static func line(_ f: Facts) -> String? {
        let list = items(f)
        return list.isEmpty ? nil : list.joined(separator: " \u{00B7} ")
    }

    /// A warning when Google lists the place as closed; nil when open or unknown.
    static func closedNotice(_ businessStatus: String?) -> String? {
        switch businessStatus {
        case "CLOSED_PERMANENTLY": return "Permanently closed, according to Google"
        case "CLOSED_TEMPORARILY": return "Temporarily closed, according to Google"
        default: return nil
        }
    }

    /// ["Brunch", "Dinner"] → "Brunch & dinner"; three or more get commas.
    static func naturalList(_ words: [String]) -> String? {
        guard let first = words.first else { return nil }
        let rest = words.dropFirst().map { $0.lowercased() }
        switch rest.count {
        case 0: return first
        case 1: return "\(first) & \(rest[0])"
        default: return "\(first), \(rest.dropLast().joined(separator: ", ")) & \(rest.last!)"
        }
    }
}
