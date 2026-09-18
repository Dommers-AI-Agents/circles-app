import Foundation
import CoreLocation

/// Home Screen quick actions (long-press the app icon) for checking in.
///
/// The static "Check In" item lives in Info.plist and always shows. This
/// planner picks the dynamic "Check in at <saved place>" rows for wherever
/// the user last was, and turns a tapped item back into the pending link the
/// scene delegate already knows how to route.
///
/// Pure: no UIKit, no services. The home controller and the scene delegate
/// apply the result to `UIApplication.shortcutItems`.
struct QuickCheckInShortcutPlanner {
    /// The static item's type (also in Info.plist).
    static let checkInType = "com.favcircles.circles.check-in"
    /// Dynamic per-place items.
    static let checkInAtPlaceType = "com.favcircles.circles.check-in-at"
    static let placeIdKey = "placeId"

    /// iOS shows four items; the static "Check In" takes one.
    static let defaultLimit = 3
    /// A city block's worth: the shops you might walk into from here.
    static let defaultRadiusMeters: CLLocationDistance = 1_500
    /// Two saves this close are the same venue (a check-in copy, a second circle).
    static let sameVenueMeters: CLLocationDistance = 30

    struct PlannedShortcut: Equatable {
        let placeId: String
        let placeName: String
    }

    /// Nearest saved places within `radius` of `around`, nearest first.
    /// No location means no rows (the static item still shows).
    ///
    /// Titles carry no distance on purpose: the list is computed when the
    /// app was last in front and read minutes or hours later, so
    /// "Check in at <name>" is the only line that stays true.
    static func plan(places: [Place],
                     around: CLLocation?,
                     limit: Int = defaultLimit,
                     radius: CLLocationDistance = defaultRadiusMeters) -> [PlannedShortcut] {
        guard let around = around, limit > 0 else { return [] }

        let located: [(Place, CLLocation)] = places.compactMap { place in
            guard !place.name.trimmingCharacters(in: .whitespaces).isEmpty,
                  let location = place.location?.clLocation,
                  location.distance(from: around) <= radius else { return nil }
            return (place, location)
        }
        .sorted { $0.1.distance(from: around) < $1.1.distance(from: around) }

        var shortcuts: [PlannedShortcut] = []
        var kept: [CLLocation] = []
        for (place, location) in located where shortcuts.count < limit {
            if kept.contains(where: { $0.distance(from: location) <= sameVenueMeters }) { continue }
            kept.append(location)
            shortcuts.append(PlannedShortcut(placeId: place.id, placeName: place.name))
        }
        return shortcuts
    }

    /// The `pendingDeepLink` string for a tapped item, or nil when the item
    /// isn't one of ours (or a per-place item lost its place id).
    static func pendingLink(forShortcutType type: String, userInfo: [String: Any]?) -> String? {
        switch type {
        case checkInType:
            return "check-in"
        case checkInAtPlaceType:
            guard let placeId = userInfo?[placeIdKey] as? String,
                  !placeId.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return "check-in:\(placeId)"
        default:
            return nil
        }
    }
}
