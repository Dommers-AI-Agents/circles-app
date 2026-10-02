import CoreLocation

/// "Refresh from Apple Maps" on Edit Place: find THIS business on Apple Maps
/// by name near the pin, rather than asking what street address sits under
/// the pin. Reverse-geocoding a wrong pin only ever confirmed the wrong
/// address (No Proof pinned at its old W Trade St spot; Apple lists it at
/// 201 W Worthington Ave — Wes, 2026-10-02). Pure; the screen runs the search.
enum AppleVenueRefresh {
    struct Candidate {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    /// How far from the pin a same-named business may be and still be "it"
    static let searchRadiusMeters: CLLocationDistance = 30_000
    /// Closer than this is the same spot: just refresh, nothing to confirm
    static let sameSpotMeters: CLLocationDistance = 60

    /// The index of the result that is this venue: same name (filler words
    /// like "Bar" or "Cafe" aside, or the saved name followed by more words,
    /// "No Proof" → "No Proof CLT"), nearest the pin, within the radius.
    static func bestMatch(for name: String, near pin: CLLocationCoordinate2D?, in candidates: [Candidate]) -> Int? {
        let key = nameKey(name)
        guard !key.isEmpty else { return nil }
        let matches = candidates.indices.filter { i in
            let other = nameKey(candidates[i].name)
            return other == key || other.hasPrefix(key + " ") || key.hasPrefix(other + " ") && !other.isEmpty
        }
        guard let pin else { return matches.first }
        let here = CLLocation(latitude: pin.latitude, longitude: pin.longitude)
        let distance = { (i: Int) in here.distance(from: CLLocation(latitude: candidates[i].coordinate.latitude,
                                                                     longitude: candidates[i].coordinate.longitude)) }
        return matches.filter { distance($0) <= searchRadiusMeters }.min { distance($0) < distance($1) }
    }

    static func nameKey(_ name: String) -> String {
        POIDuplicateMatcher.normalizedName(name).split(separator: " ").map(String.init)
            .filter { !POIDuplicateMatcher.fillerWords.contains($0) }
            .joined(separator: " ")
    }
}
