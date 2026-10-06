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

    /// Close enough to name a visit without asking
    static let autoNameRadius: Double = 60
    /// How far the picker looks (a big store's pin can sit across the lot)
    static let searchRadius: Double = 120
    /// How many the picker lists
    static let maxChoices = 6

    /// A name that's really an address or a placeholder, so worth replacing.
    static func looksLikeAddress(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Unknown Place" { return true }
        // "1120 S Tryon St", "400, E Morehead St"
        guard let first = trimmed.first, first.isNumber else { return false }
        let words = trimmed.split(whereSeparator: { $0 == " " || $0 == "," })
        return words.count >= 2 && words[0].allSatisfy { $0.isNumber || $0 == "-" }
    }

    /// The nearest candidate inside `autoNameRadius`, or nil.
    static func autoName(from candidates: [Candidate]) -> Candidate? {
        candidates.filter { $0.distance <= autoNameRadius }.min { $0.distance < $1.distance }
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
