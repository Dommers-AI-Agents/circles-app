import Foundation

/// The words on the card a tapped map place opens (Wes, 2026-11-12: "make
/// this bubble prettier and better"): what kind of place it is and how far.
enum MapPlaceCalloutCopy {
    /// "MKPOICategoryNationalPark" → "National park"; nil for an unknown one
    static func categoryName(rawValue: String?) -> String? {
        guard var raw = rawValue, !raw.isEmpty else { return nil }
        if raw.hasPrefix("MKPOICategory") { raw.removeFirst("MKPOICategory".count) }
        guard !raw.isEmpty else { return nil }
        var words: [String] = []
        var current = ""
        for character in raw {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        // Two Apple names read better spelled out
        switch raw {
        case "EVCharger": return "EV charger"
        case "ATM": return "ATM"
        default: break
        }
        let sentence = words.joined(separator: " ").lowercased()
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    /// "0.4 mi", "250 ft", "12 mi"; nil when we don't know where they are
    static func distance(meters: Double?) -> String? {
        guard let meters, meters >= 0 else { return nil }
        let feet = meters * 3.28084
        if feet < 1000 { return "\(max(10, Int((feet / 10).rounded()) * 10)) ft" }
        let miles = meters / 1609.344
        return miles < 10 ? String(format: "%.1f mi", miles) : "\(Int(miles.rounded())) mi"
    }

    /// The line under the name: "Restaurant · 0.4 mi"
    static func detail(category: String?, meters: Double?) -> String? {
        let parts = [categoryName(rawValue: category), distance(meters: meters)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
