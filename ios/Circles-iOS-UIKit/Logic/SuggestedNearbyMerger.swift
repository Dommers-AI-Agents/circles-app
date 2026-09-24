import Foundation
import CoreLocation

/// One row of the search overlay's nearby section: a venue from the shared
/// catalog (someone on FavCircles saved it) or one Apple Maps knows.
enum SuggestedRow {
    case global(GlobalPlace)
    case apple(Place)

    /// The row as a Place, whichever side it came from.
    var place: Place {
        switch self {
        case .global(let global): return global.toLegacyPlace()
        case .apple(let place): return place
        }
    }

    var id: String {
        switch self {
        case .global(let global): return global.id
        case .apple(let place): return place.id
        }
    }
}

/// Merges the two nearby channels into the rows under MORE NEARBY / SUGGESTED.
///
/// Anything that is really one of the person's saved places is not a
/// suggestion — it is already in PLACES. When the catalog and Apple both know
/// a venue, the catalog copy wins: it carries a real id and the social data.
/// Nearest first, a short list.
enum SuggestedNearbyMerger {
    static let cap = 8

    static func merge(global: [GlobalPlace], apple: [Place], saved: [Place],
                      from origin: CLLocation?) -> [(row: SuggestedRow, distance: CLLocationDistance?)] {
        // Names normalised once per pass, not once per pair (see NameKey)
        let keyedSaved = saved.map(POIDuplicateMatcher.KeyedPlace.init)
        let isSaved: (Place) -> Bool = { place in
            let key = POIDuplicateMatcher.NameKey(place.name)
            guard let coordinate = place.location?.clLocation?.coordinate else {
                return keyedSaved.contains { $0.key.normalized == key.normalized }
            }
            return keyedSaved.contains { POIDuplicateMatcher.isSearchHit(key: key, coordinate: coordinate, saved: $0) }
        }
        var rows: [SuggestedRow] = []
        var places: [Place] = []
        var keptKeys: [POIDuplicateMatcher.KeyedPlace] = []
        for g in global {
            let place = g.toLegacyPlace()
            guard !isSaved(place) else { continue }
            rows.append(.global(g)); places.append(place); keptKeys.append(.init(place))
        }
        for a in apple {
            guard !isSaved(a) else { continue }
            // Already offered by the catalog? Keep the catalog copy.
            if let coordinate = a.location?.clLocation?.coordinate {
                let key = POIDuplicateMatcher.NameKey(a.name)
                if keptKeys.contains(where: { POIDuplicateMatcher.isSearchHit(key: key, coordinate: coordinate, saved: $0) }) { continue }
            }
            rows.append(.apple(a)); places.append(a); keptKeys.append(.init(a))
        }
        let byId = Dictionary(uniqueKeysWithValues: zip(places.map(\.id), rows))
        return DistancePlaceSorter.sorted(places, from: origin).prefix(cap).compactMap { entry in
            byId[entry.place.id].map { (row: $0, distance: entry.distance) }
        }
    }
}
