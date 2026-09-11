import Foundation
import CoreLocation

/// Whether a map point of interest is already one of the user's places:
/// a name match (either name contains the other, case-insensitive) within
/// about a hundred meters.
enum POIDuplicateMatcher {
    static let radiusMeters: CLLocationDistance = 100

    static func namesMatch(_ a: String, _ b: String) -> Bool {
        let lhs = a.lowercased()
        let rhs = b.lowercased()
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
    }

    /// The first place that matches by name and proximity, in list order.
    static func existingPlace(named name: String, at coordinate: CLLocationCoordinate2D, in places: [Place]) -> Place? {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        for place in places {
            guard let placeLocation = place.location?.clLocation else { continue }
            let locationMatch = placeLocation.distance(from: target) < radiusMeters
            if namesMatch(place.name, name) && locationMatch {
                return place
            }
        }
        return nil
    }
}
