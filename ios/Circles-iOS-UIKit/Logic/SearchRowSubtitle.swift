import Foundation

/// The second line of a home search result (Wes, 2026-11-07: the full
/// address was cut off anyway, and who saved it is the useful part):
/// "0.2 mi · Saved by 5 · Camden Rd" for your places and your network's,
/// "0.6 mi · On FavCircles" / "1.2 mi · Apple Maps" for nearby ones.
enum SearchRowSubtitle {
    enum Source: Equatable {
        /// Saved by you or your network: how many of them, whether you're one,
        /// and the one saver's first name when it's a single other person
        case saved(Savers)
        /// Saved on FavCircles, not by your network
        case favCircles
        /// An Apple Maps place nobody has saved
        case appleMaps
    }

    /// How many of your people saved one venue, and whether you did
    struct Savers: Equatable {
        let count: Int
        let includesYou: Bool
        var firstName: String? = nil
    }

    /// Distinct savers per venue (Place.venueDedupeKey) among the matched
    /// saves, before they collapse to one row per venue.
    static func savers(in places: [Place]) -> [String: Savers] {
        var groups: [String: [Place]] = [:]
        for place in places { groups[place.venueDedupeKey, default: []].append(place) }
        return groups.mapValues { group in
            let people = Set(group.map(\.addedBy))
            let name = group.first?.addedByUser?.displayName.split(separator: " ").first.map(String.init)
            return Savers(count: people.count, includesYou: group.contains { $0.isAddedByCurrentUser },
                          firstName: people.count == 1 ? name : nil)
        }
    }

    static func make(distance: String?, source: Source, address: String) -> String {
        var parts: [String] = []
        if let distance, !distance.isEmpty { parts.append(distance) }
        switch source {
        case .saved(let savers):
            if savers.count <= 1 {
                parts.append(savers.includesYou ? "Saved by you" : "Saved by \(savers.firstName ?? "1 person")")
            } else {
                parts.append(savers.includesYou ? "Saved by you + \(savers.count - 1)" : "Saved by \(savers.count)")
            }
            if let street = street(from: address) { parts.append(street) }
        case .favCircles:
            parts.append("On FavCircles")
        case .appleMaps:
            parts.append("Apple Maps")
        }
        return parts.joined(separator: " · ")
    }

    /// "1700 Camden Rd, Charlotte, NC" → "Camden Rd"; "1514, S Church St, …"
    /// (the old import's comma after the number) → "S Church St".
    static func street(from address: String) -> String? {
        let parts = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts.prefix(2) {
            let words = part.split(separator: " ")
            let rest = words.first.map { $0.allSatisfy { $0.isNumber || $0 == "-" } } == true ? words.dropFirst() : words[...]
            let street = rest.joined(separator: " ")
            if !street.isEmpty && !street.allSatisfy({ $0.isNumber }) { return street }
        }
        return nil
    }
}
