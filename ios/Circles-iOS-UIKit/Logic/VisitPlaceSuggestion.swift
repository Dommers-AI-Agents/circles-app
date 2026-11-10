import Foundation

/// Which business a visit was at. A visit used to be named from reverse
/// geocoding alone, which gives a street address ("1120 S Tryon St"), not
/// the restaurant inside it (Wes, 2026-10-05). The businesses Apple Maps
/// lists around the spot are the candidates; the nearest one close enough
/// names a new visit, and the visit page lists them all to pick from.
enum VisitPlaceSuggestion {
    struct Candidate: Equatable {
        let name: String
        let address: String
        let category: String?   // PlaceCategory raw value
        let distance: Double    // meters from the visit
    }

    /// Close enough to name a visit without asking, when the fix is good
    static let autoNameRadius: Double = 60
    /// The most a rough fix may stretch that (iOS visits are often 50–150 m
    /// off, and a store's pin sits mid-building) (Wes, 2026-11-10)
    static let maxAutoNameRadius: Double = 150
    /// Nearer than this, the nearest business wins outright
    static let sureDistance: Double = 30
    /// Farther than `sureDistance`, the runner-up must be this many times as
    /// far, or it's a toss-up and the person picks
    static let clearMargin: Double = 1.5
    /// How far the picker looks (a big store's pin can sit across the lot)
    static let searchRadius: Double = 150
    /// How many the picker lists
    static let maxChoices = 6

    /// Street words a bare street name ends with ("S Tryon St")
    private static let streetSuffixes: Set<String> = [
        "st", "street", "ave", "avenue", "rd", "road", "blvd", "boulevard", "dr", "drive",
        "ln", "lane", "hwy", "highway", "pkwy", "parkway", "ct", "court", "pl", "place",
        "way", "ter", "terrace", "cir", "circle", "trl", "trail", "fwy", "expy"
    ]

    /// A name that's really an address or a placeholder, so worth replacing.
    /// `address` is the visit's own address: a name that's just one piece of
    /// it ("S Tryon St", "Charlotte") is no business name either.
    static func looksLikeAddress(_ name: String, address: String? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Unknown Place" { return true }
        let words = trimmed.split(whereSeparator: { $0 == " " || $0 == "," })
        // "1120 S Tryon St", "400, E Morehead St"
        if let first = words.first, first.first?.isNumber == true,
           words.count >= 2, first.allSatisfy({ $0.isNumber || $0 == "-" }) { return true }
        // "S Tryon St", "Morehead Street": a bare street
        if words.count >= 2, words.count <= 4, let last = words.last,
           streetSuffixes.contains(last.lowercased().trimmingCharacters(in: .punctuationCharacters)) { return true }
        // A piece of the visit's own address (its street, city or state)
        if let address {
            let key = trimmed.lowercased()
            let pieces = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if pieces.contains(key) { return true }
            if let street = pieces.first {
                let bare = street.split(separator: " ").drop { $0.allSatisfy { $0.isNumber || $0 == "-" } }.joined(separator: " ")
                if !bare.isEmpty && bare == key { return true }
            }
        }
        return false
    }

    /// How far a business may be to name the visit: the fix's own accuracy,
    /// at least `autoNameRadius`, at most `maxAutoNameRadius`.
    static func reach(accuracy: Double?) -> Double {
        guard let accuracy, accuracy > 0 else { return autoNameRadius }
        return min(maxAutoNameRadius, max(autoNameRadius, accuracy))
    }

    /// The business to name a visit for, or nil when none is close enough or
    /// two are about as close (then the person picks; a wrong name is worse
    /// than "Near 1120 S Tryon St").
    static func autoName(from candidates: [Candidate], accuracy: Double? = nil) -> Candidate? {
        let inReach = candidates.filter { $0.distance <= reach(accuracy: accuracy) }.sorted { $0.distance < $1.distance }
        guard let nearest = inReach.first else { return nil }
        if nearest.distance <= sureDistance { return nearest }
        let runnerUp = inReach.dropFirst().first { $0.name.lowercased() != nearest.name.lowercased() }
        if let runnerUp, runnerUp.distance < nearest.distance * clearMargin { return nil }
        return nearest
    }

    /// Still named for its address, so worth looking up again
    static func needsName(_ visit: PlaceVisit) -> Bool {
        !visit.dismissed && looksLikeAddress(visit.placeName, address: visit.placeAddress)
    }

    /// The list row for a visit we couldn't name: "Near 1120 S Tryon St"
    static func nearTitle(_ visit: PlaceVisit) -> String {
        let street = visit.placeName.trimmingCharacters(in: .whitespaces)
        if street.isEmpty || street == "Unknown Place" {
            return "Near " + (visit.placeAddress.split(separator: ",").first.map(String.init) ?? "an unnamed place")
        }
        return "Near \(street)"
    }

    /// The picker's list: nearest first, one per name, at most `maxChoices`.
    static func choices(from candidates: [Candidate]) -> [Candidate] {
        var seen = Set<String>()
        return candidates
            .filter { $0.distance <= searchRadius }
            .sorted { $0.distance < $1.distance }
            .filter { seen.insert($0.name.lowercased()).inserted }
            .prefix(maxChoices)
            .map { $0 }
    }

    /// "40 m away" / "0.1 mi away"
    static func distanceText(_ meters: Double) -> String {
        meters < 150 ? "\(Int(meters.rounded())) m away" : String(format: "%.1f mi away", meters / 1609.34)
    }
}
