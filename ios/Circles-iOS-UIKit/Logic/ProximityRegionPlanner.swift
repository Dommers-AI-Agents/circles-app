import Foundation
import CoreLocation

/// Picks which saved places get a location-triggered "you're nearby, check
/// in?" local notification.
///
/// iOS monitors at most 20 regions per app (shared between
/// `UNLocationNotificationTrigger` and `CLLocationManager` regions), so the
/// plan is the nearest saved venues to where the user last was. The app
/// replans every time it comes forward, which is how the set follows the
/// user around.
///
/// Pure: no UserNotifications, no services. `ProximityNotificationScheduler`
/// turns the result into requests.
struct ProximityRegionPlanner {
    /// iOS's per-app region cap.
    static let regionLimit = 20
    /// Trigger radius. Wider than the in-app chip's 50 m because region entry
    /// fires immediately with no dwell and GPS drift near buildings is real.
    static let defaultRadiusMeters: CLLocationDistance = 100
    /// Two saves this close together are the same venue (a check-in copy, a
    /// second circle) and get one region.
    static let sameVenueMeters: CLLocationDistance = 30
    /// Pending-request identifier prefix, so stale requests are removable
    /// without persisting a list.
    static let identifierPrefix = "proximity."

    struct PlannedRegion: Equatable {
        let placeId: String
        let placeName: String
        let coordinate: CLLocationCoordinate2D
        let radius: CLLocationDistance

        var identifier: String { ProximityRegionPlanner.identifierPrefix + placeId }

        static func == (lhs: PlannedRegion, rhs: PlannedRegion) -> Bool {
            lhs.placeId == rhs.placeId && lhs.placeName == rhs.placeName
                && lhs.coordinate.latitude == rhs.coordinate.latitude
                && lhs.coordinate.longitude == rhs.coordinate.longitude
                && lhs.radius == rhs.radius
        }
    }

    static func placeId(fromIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let id = String(identifier.dropFirst(identifierPrefix.count))
        return id.isEmpty ? nil : id
    }

    /// - Parameters:
    ///   - places: the user's own saved places (the disk cache set).
    ///   - around: where the user is; nil means no plan (keep whatever is scheduled).
    ///   - excludedPlaceIds: places already prompted today, so they are not rescheduled.
    static func plan(places: [Place],
                     around: CLLocation?,
                     excludedPlaceIds: Set<String> = [],
                     limit: Int = regionLimit,
                     radius: CLLocationDistance = defaultRadiusMeters) -> [PlannedRegion] {
        guard let around = around, limit > 0 else { return [] }

        let located: [(Place, CLLocation)] = places.compactMap { place in
            guard !excludedPlaceIds.contains(place.id),
                  !place.name.trimmingCharacters(in: .whitespaces).isEmpty,
                  let location = place.location?.clLocation else { return nil }
            return (place, location)
        }
        .sorted { $0.1.distance(from: around) < $1.1.distance(from: around) }

        var regions: [PlannedRegion] = []
        var kept: [CLLocation] = []
        for (place, location) in located where regions.count < limit {
            if kept.contains(where: { $0.distance(from: location) <= sameVenueMeters }) { continue }
            kept.append(location)
            regions.append(PlannedRegion(placeId: place.id,
                                         placeName: place.name,
                                         coordinate: location.coordinate,
                                         radius: radius))
        }
        return regions
    }
}
