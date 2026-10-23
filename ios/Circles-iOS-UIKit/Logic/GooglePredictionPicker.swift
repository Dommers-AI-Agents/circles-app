import Foundation

/// Picks the Google suggestion that is the business the user chose
/// (2026-10-23). Google often names it differently ("Uptown Yolk" for
/// Apple's "Uptown Yolk Cafe"), and when it can't match it offers the street
/// address first, which used to be taken as a fallback and became the
/// venue's name. Now: never an address, and only a name that shares the
/// business's words; otherwise no Google match at all.
enum GooglePredictionPicker {
    struct Candidate: Equatable {
        let name: String
        let types: [String]
    }

    /// Google types for an entry that is only an address
    static let addressTypes: Set<String> = [
        "street_address", "premise", "subpremise", "route", "intersection",
        "street_number", "postal_code", "plus_code", "geocode"
    ]

    static func isAddressOnly(_ types: [String]) -> Bool {
        guard !types.isEmpty else { return false }
        if types.contains("establishment") || types.contains("point_of_interest") { return false }
        return types.contains { addressTypes.contains($0) }
    }

    /// The index of the candidate to use, or nil for "no Google match"
    static func pick(name: String, from candidates: [Candidate]) -> Int? {
        let wanted = tokens(name)
        guard !wanted.isEmpty else { return nil }
        let usable = candidates.enumerated().filter { !isAddressOnly($0.element.types) }
        if let exact = usable.first(where: { tokens($0.element.name) == wanted }) { return exact.offset }
        return usable.first(where: { namesMatch(wanted, tokens($0.element.name)) })?.offset
    }

    /// One name's words all appear in the other's ("uptown yolk" ⊂ "uptown yolk cafe")
    static func namesMatch(_ a: [String], _ b: [String]) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        let sa = Set(a), sb = Set(b)
        return sa.isSubset(of: sb) || sb.isSubset(of: sa)
    }

    static func tokens(_ s: String) -> [String] {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0 != "the" }
    }
}
