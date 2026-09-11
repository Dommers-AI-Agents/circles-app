import Foundation

/// Tells a street-address search result ("300 East Blvd") from a business,
/// and whether a nearby business's name is close enough to that address to
/// suggest it instead. Wes's rule: only suggest a business with the same or
/// almost-same name.
enum BareAddressHeuristic {
    /// True when a map item is a street-address entity rather than a business:
    /// no POI category, and its name is just the address line MapKit builds
    /// ("300 East Blvd" / "121 W Trade St").
    static func isBareAddress(name: String?, hasPointOfInterestCategory: Bool,
                              subThoroughfare: String?, thoroughfare: String?) -> Bool {
        guard !hasPointOfInterestCategory, let name = name, !name.isEmpty else { return false }
        let streetLine = [subThoroughfare, thoroughfare]
            .compactMap { $0 }.joined(separator: " ")
        let normName = normalize(name)
        guard !normName.isEmpty else { return false }
        return normName == normalize(streetLine)
            || normName == normalize(thoroughfare ?? "")
    }

    /// Business/address name kinship: the business name's tokens are contained
    /// in the address line ("300 East" ⊂ "300 East Blvd") or vice versa.
    static func namesRelated(business: String, address: String) -> Bool {
        let b = tokens(business)
        let a = tokens(address)
        guard !b.isEmpty, !a.isEmpty else { return false }
        let bSet = Set(b), aSet = Set(a)
        if bSet.isSubset(of: aSet) || aSet.isSubset(of: bSet) { return true }
        // Prefix kinship covers abbreviation drift ("W Trade" vs "West Trade")
        let overlap = bSet.intersection(aSet).count
        return overlap >= 2 && overlap >= b.count - 1
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func tokens(_ s: String) -> [String] {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
