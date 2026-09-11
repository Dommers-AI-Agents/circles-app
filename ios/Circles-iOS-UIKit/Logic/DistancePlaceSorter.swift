import Foundation
import CoreLocation

/// Orders places for a "nearest first" list: by distance from a reference
/// point, with unlocated places last (alphabetical among themselves). Shared
/// by the full-screen map's list and the profile map's list.
enum DistancePlaceSorter {
    typealias Entry = (place: Place, distance: CLLocationDistance?)

    static func sorted(_ places: [Place], from reference: CLLocation) -> [Entry] {
        places.map { place -> Entry in
            let distance = place.location?.clLocation.map { reference.distance(from: $0) }
            return (place: place, distance: distance)
        }.sorted { lhs, rhs in
            switch (lhs.distance, rhs.distance) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.place.name.localizedCaseInsensitiveCompare(rhs.place.name) == .orderedAscending
            }
        }
    }
}
