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

// MARK: - Search hits (Apple Maps results against saved places)

extension POIDuplicateMatcher {
    /// Tighter than the add-place duplicate radius: a search result is "this
    /// saved place" only when it is practically on top of it, or shares its
    /// name outright.
    static let searchHitRadiusMeters: CLLocationDistance = 75

    /// "Pasta & Provisions", "pasta and provisions", "The Pasta & Provisions."
    /// are one name.
    static func normalizedName(_ name: String) -> String {
        var text = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "&", with: " and ")
        text = text.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }.map(String.init).joined()
        var words = text.split(separator: " ").map(String.init)
        if words.first == "the" { words.removeFirst() }
        return words.joined(separator: " ")
    }

    /// Whether a venue found by name and coordinate IS this saved place:
    /// within 75 m, or the same normalised name.
    static func isSearchHit(name: String, coordinate: CLLocationCoordinate2D, place: Place) -> Bool {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let placeLocation = place.location?.clLocation, placeLocation.distance(from: target) <= searchHitRadiusMeters {
            return true
        }
        let mine = normalizedName(place.name)
        return !mine.isEmpty && mine == normalizedName(name)
    }

    /// Splits search results into the saved places they turn out to be and
    /// the venues nobody has saved. Each saved place is claimed once.
    static func partition(candidates: [Place], saved: [Place]) -> (matched: [Place], unsaved: [Place]) {
        var matched: [Place] = []
        var claimed = Set<String>()
        var unsaved: [Place] = []
        for candidate in candidates {
            guard let coordinate = candidate.location?.clLocation?.coordinate else { unsaved.append(candidate); continue }
            if let hit = saved.first(where: { !claimed.contains($0.id) && isSearchHit(name: candidate.name, coordinate: coordinate, place: $0) }) {
                claimed.insert(hit.id)
                matched.append(hit)
            } else {
                unsaved.append(candidate)
            }
        }
        return (matched, unsaved)
    }
}
