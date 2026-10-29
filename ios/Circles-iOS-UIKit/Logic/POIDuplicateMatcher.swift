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

    /// Words that say nothing about WHICH venue it is.
    static let fillerWords: Set<String> = [
        "the", "and", "of", "at", "on", "in", "a", "an", "co", "inc", "llc",
        "bar", "grill", "restaurant", "cafe", "kitchen", "shop", "store"
    ]

    /// The words of a name that can tell it apart from its neighbours.
    static func significantWords(_ name: String) -> Set<String> {
        Set(normalizedName(name).split(separator: " ").map(String.init)
            .filter { $0.count >= 3 && !fillerWords.contains($0) })
    }

    /// A name, normalised once. Every comparison of a search result against
    /// a saved place used to normalise both names (and split both into
    /// words) on the spot — with a thousand saved places and twenty results
    /// that was a hundred thousand normalisations per pass, several passes
    /// per keystroke, and the whole search sheet stuttered (2026-09-24).
    struct NameKey {
        let normalized: String
        let words: Set<String>

        init(_ name: String) {
            let normalized = POIDuplicateMatcher.normalizedName(name)
            self.normalized = normalized
            self.words = Set(normalized.split(separator: " ").map(String.init)
                .filter { $0.count >= 3 && !POIDuplicateMatcher.fillerWords.contains($0) })
        }
    }

    /// A saved place with its key computed once per pass.
    struct KeyedPlace {
        let place: Place
        let key: NameKey
        let location: CLLocation?

        init(_ place: Place) {
            self.place = place
            self.key = NameKey(place.name)
            self.location = place.location?.clLocation
        }
    }

    /// Whether a venue found by name and coordinate IS this saved place: the
    /// same normalised name, or within 75 m AND sharing a telling word.
    /// Proximity alone is not enough — downtown, "Pizz" claimed every save
    /// within a block of a pizzeria as a match (70 rows for four pizzerias).
    static func isSearchHit(name: String, coordinate: CLLocationCoordinate2D, place: Place) -> Bool {
        isSearchHit(key: NameKey(name), coordinate: coordinate, saved: KeyedPlace(place))
    }

    static func isSearchHit(key theirs: NameKey, coordinate: CLLocationCoordinate2D, saved: KeyedPlace) -> Bool {
        let mine = saved.key
        guard !mine.normalized.isEmpty, !theirs.normalized.isEmpty else { return false }
        if mine.normalized == theirs.normalized { return true }
        guard let placeLocation = saved.location else { return false }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard placeLocation.distance(from: target) <= searchHitRadiusMeters else { return false }
        return !mine.words.isDisjoint(with: theirs.words)
    }

    /// Splits search results into the saved places they turn out to be and
    /// the venues nobody has saved. Each saved place is claimed once.
    static func partition(candidates: [Place], saved: [Place]) -> (matched: [Place], unsaved: [Place]) {
        partition(candidates: candidates, index: SavedPlaceIndex(saved))
    }

    static func partition(candidates: [Place], index: SavedPlaceIndex) -> (matched: [Place], unsaved: [Place]) {
        var matched: [Place] = []
        var claimed = Set<String>()
        var unsaved: [Place] = []
        for candidate in candidates {
            guard let coordinate = candidate.location?.clLocation?.coordinate else { unsaved.append(candidate); continue }
            let key = NameKey(candidate.name)
            if let hit = index.hits(key: key, coordinate: coordinate).first(where: { !claimed.contains($0.place.id) }) {
                claimed.insert(hit.place.id)
                matched.append(hit.place)
            } else {
                unsaved.append(candidate)
            }
        }
        return (matched, unsaved)
    }
}

/// The saved places a search compares against, keyed ONCE per change of the
/// saved set (not once per pass): by normalised name, and by a ~110 m grid so
/// the "within 75 m" rule only looks at the cell and its neighbours. Each
/// result used to scan every saved place (O(results × saved) per pass, several
/// passes per keystroke).
struct SavedPlaceIndex {
    private let keyed: [POIDuplicateMatcher.KeyedPlace]
    private let byName: [String: [Int]]
    private let byCell: [Cell: [Int]]

    private struct Cell: Hashable { let lat: Int; let lng: Int }
    /// ~111 m of latitude; with the 3×3 neighbourhood it covers the 75 m rule
    private static let step = 0.001

    private static func cell(_ c: CLLocationCoordinate2D) -> Cell {
        Cell(lat: Int((c.latitude / step).rounded(.down)), lng: Int((c.longitude / step).rounded(.down)))
    }

    init(_ saved: [Place]) {
        let keyed = saved.map(POIDuplicateMatcher.KeyedPlace.init)
        var byName: [String: [Int]] = [:]
        var byCell: [Cell: [Int]] = [:]
        for (i, k) in keyed.enumerated() {
            if !k.key.normalized.isEmpty { byName[k.key.normalized, default: []].append(i) }
            if let c = k.location?.coordinate { byCell[Self.cell(c), default: []].append(i) }
        }
        self.keyed = keyed
        self.byName = byName
        self.byCell = byCell
    }

    var isEmpty: Bool { keyed.isEmpty }

    /// Saved places this venue IS (POIDuplicateMatcher.isSearchHit), in the
    /// saved set's original order.
    func hits(key: POIDuplicateMatcher.NameKey, coordinate: CLLocationCoordinate2D) -> [POIDuplicateMatcher.KeyedPlace] {
        var candidates = Set(byName[key.normalized] ?? [])
        let center = Self.cell(coordinate)
        for dLat in -1...1 {
            for dLng in -1...1 {
                candidates.formUnion(byCell[Cell(lat: center.lat + dLat, lng: center.lng + dLng)] ?? [])
            }
        }
        return candidates.sorted()
            .map { keyed[$0] }
            .filter { POIDuplicateMatcher.isSearchHit(key: key, coordinate: coordinate, saved: $0) }
    }

    /// Is this place (by name, and by name + proximity when it has a point)
    /// one of the saved places?
    func contains(_ place: Place) -> Bool {
        let key = POIDuplicateMatcher.NameKey(place.name)
        guard let coordinate = place.location?.clLocation?.coordinate else {
            return byName[key.normalized] != nil
        }
        return !hits(key: key, coordinate: coordinate).isEmpty
    }
}
