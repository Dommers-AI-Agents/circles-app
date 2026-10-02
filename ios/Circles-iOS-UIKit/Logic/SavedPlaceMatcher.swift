import Foundation

/// Which already-loaded places (yours, your network's) match what was typed
/// into a place search. The POI search only asks Apple Maps near you, so a
/// saved place that is far away or that Apple doesn't know by that name
/// never appeared ("Knight" never found "Sgroi Innovations - KnightATV" from
/// Charlotte — Wes, 2026-10-02). Pure; the pickers show these above the
/// Apple Maps suggestions.
enum SavedPlaceMatcher {

    /// - Returns: up to `limit` items whose name (or, after those, address)
    ///   matches every typed word, in the order given (callers pass them
    ///   nearest first), one per `key` (the same venue saved twice shows once).
    static func matches<T>(_ query: String, in items: [T], limit: Int = 6,
                           name: (T) -> String, address: (T) -> String, key: (T) -> String) -> [T] {
        let tokens = words(query)
        guard !tokens.isEmpty else { return [] }
        var seen = Set<String>()
        var byName: [T] = []
        var byAddress: [T] = []
        for item in items {
            guard !seen.contains(key(item)) else { continue }
            if fits(tokens, query, name(item)) {
                seen.insert(key(item)); byName.append(item)
            } else if fits(tokens, query, address(item)) {
                seen.insert(key(item)); byAddress.append(item)
            }
        }
        return Array((byName + byAddress).prefix(limit))
    }

    /// Every typed word starts a word of the text ("knight" → "KnightATV"),
    /// or the whole query appears with spaces ignored ("knight atv").
    private static func fits(_ tokens: [String], _ query: String, _ text: String) -> Bool {
        let textWords = words(text)
        guard !textWords.isEmpty else { return false }
        if tokens.allSatisfy({ t in textWords.contains { $0.hasPrefix(t) } }) { return true }
        let squashedQuery = tokens.joined()
        return squashedQuery.count >= 3 && textWords.joined().contains(squashedQuery)
    }

    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
