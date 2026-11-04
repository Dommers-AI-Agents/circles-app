import Foundation

/// The Locals tab's search box (Wes, 2026-11-04: "Panthers football"). Rows
/// already on the tab filter as you type; after a pause the server searches
/// Ticketmaster's whole listing (a year out, 100 miles, anywhere when nothing
/// is near) plus store events and library programs.
enum LocalsSearch {
    /// Shorter than this, only the rows on screen are filtered
    static let minRemoteLength = 2
    static let debounce: TimeInterval = 0.4

    static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Every word of the query appears somewhere in `fields`, any case or accent
    static func matches(_ fields: [String?], query: String) -> Bool {
        let wanted = words(query)
        guard !wanted.isEmpty else { return false }
        let haystack = fold(fields.compactMap { $0 }.joined(separator: " "))
        return wanted.allSatisfy { haystack.contains($0) }
    }

    static func matches(_ event: NearbyEvent, query: String) -> Bool {
        matches([event.name, event.venueName, event.sourceName, event.category, event.city, event.message], query: query)
    }

    /// The server's answer with the tab's own matches it doesn't have; stores
    /// on FavCircles first, then soonest.
    static func mergeEvents(local: [NearbyEvent], remote: [NearbyEvent]) -> [NearbyEvent] {
        let known = Set(remote.map(\.id))
        let merged = remote + local.filter { !known.contains($0.id) }
        return merged.enumerated().sorted { a, b in
            if a.element.isStoreEvent != b.element.isStoreEvent { return a.element.isStoreEvent }
            let ka = startKey(a.element), kb = startKey(b.element)
            return ka == kb ? a.offset < b.offset : ka < kb
        }.map(\.element)
    }

    private static func startKey(_ event: NearbyEvent) -> String {
        "\(event.startLocalDate) \(event.startLocalTime ?? "99")"
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
