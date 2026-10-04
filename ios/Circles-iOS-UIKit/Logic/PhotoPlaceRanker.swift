import CoreLocation

/// Which place a group of photos was taken at. Your own saves near the spot
/// come first (photos go into that place); then businesses Apple Maps lists
/// near it, nearest first, minus home addresses and minus anything that is
/// one of those saves. Pure.
enum PhotoPlaceRanker {
    struct Saved { let id: String; let name: String; let coordinate: CLLocationCoordinate2D }
    struct POI { let name: String; let coordinate: CLLocationCoordinate2D; let isResidential: Bool }

    enum Pick: Equatable {
        case saved(id: String, meters: Double)
        case poi(index: Int, meters: Double)
    }

    static let savedRadiusMeters: CLLocationDistance = 75
    static let poiRadiusMeters: CLLocationDistance = 100

    static func rank(center: CLLocationCoordinate2D, saved: [Saved], pois: [POI]) -> [Pick] {
        let d = { (c: CLLocationCoordinate2D) in PhotoPlaceGrouper.distance(center, c) }
        let nearSaved = saved.map { ($0, d($0.coordinate)) }
            .filter { $0.1 <= savedRadiusMeters }
            .sorted { $0.1 < $1.1 }
        let nearPOIs = pois.indices.map { ($0, d(pois[$0].coordinate)) }
            .filter { i, meters in
                let poi = pois[i]
                guard meters <= poiRadiusMeters, !poi.isResidential, !poi.name.isEmpty else { return false }
                // Already one of the saves listed above: don't offer it twice
                return !nearSaved.contains { s, _ in
                    POIDuplicateMatcher.namesMatch(s.name, poi.name)
                        && PhotoPlaceGrouper.distance(s.coordinate, poi.coordinate) <= POIDuplicateMatcher.radiusMeters
                }
            }
            .sorted { $0.1 < $1.1 }
        return nearSaved.map { .saved(id: $0.0.id, meters: $0.1) } + nearPOIs.map { .poi(index: $0.0, meters: $0.1) }
    }
}
