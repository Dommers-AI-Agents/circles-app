import Foundation

/// Sticker Venues' search (Wes, 2026-11-07: 160+ stores, find one quickly).
/// A store matches when every word typed appears somewhere in its name,
/// address, contact or codes, ignoring case and accents, in any order
/// ("wooden coffee" finds Wooden Robot Coffee Bar).
enum VenueAdminSearch {
    static func matches(_ query: String, fields: [String?]) -> Bool {
        let words = PlaceSearchText.fold(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let text = PlaceSearchText.fold(fields.compactMap { $0 }.joined(separator: " "))
        return words.allSatisfy { text.contains($0) }
    }

    static func fields(of venue: AdminVenue) -> [String?] {
        [venue.venueName, venue.placeAddress, venue.contactName, venue.contactEmail, venue.windowCode, venue.registerCode]
    }

    static func filter(_ venues: [AdminVenue], query: String) -> [AdminVenue] {
        venues.filter { matches(query, fields: fields(of: $0)) }
    }
}
