import Foundation

/// What the home search bar is looking for.
///
/// Typing a name is ambiguous — "Nick" is both a person and Nickyo's Rodeo —
/// so the person says which, and the search stops guessing. Places is the
/// default because the home screen is a map.
enum HomeSearchMode: Int, CaseIterable {
    case places
    case people

    var title: String {
        switch self {
        case .places: return "Places"
        case .people: return "People"
        }
    }

    /// The text the map should filter by in this mode — nil in People mode,
    /// which hands the map back untouched.
    func filtersMap(_ query: String) -> String? {
        self == .places ? query : nil
    }

    var placeholder: String {
        switch self {
        case .places: return "Search places"
        case .people: return "Search people"
        }
    }
}

/// How many rows of each kind the search results sheet shows, and whether
/// the map filters with the query.
///
/// This exists because of a real miss: place matches were routed to the map
/// only, on the reasoning that the dropdown would cover it. Searching "Nick"
/// then filtered the map to Nickyo's Rodeo correctly while the dropdown showed
/// a stranger called Ethan and no way to tap the place.
///
/// Since 2026-09-24 the results live in a scrollable sheet under the map, so
/// every matched place gets a row (nearest first) — the list and the pins show
/// the same set, and the handle says how many.
struct HomeSearchPlan: Equatable {
    var placeRows: Int
    var suggestedRows: Int
    var peopleRows: Int
    /// People mode leaves the map alone: filtering pins by a person's name
    /// matches place names by accident and empties the map for no reason.
    var filtersMap: Bool

    static let maxSuggestedRows = 6
    /// When your own places already match, nearby venues are extras.
    static let maxExtraSuggestedRows = 3
    static let maxPeopleRows = 6

    var hasRows: Bool { placeRows + suggestedRows + peopleRows > 0 }

    static func make(mode: HomeSearchMode,
                     matchedPlaces: Int,
                     suggestedPlaces: Int,
                     people: Int) -> HomeSearchPlan {
        switch mode {
        case .people:
            return HomeSearchPlan(
                placeRows: 0,
                suggestedRows: 0,
                peopleRows: min(max(people, 0), maxPeopleRows),
                filtersMap: false
            )
        case .places:
            let matched = max(matchedPlaces, 0)
            return HomeSearchPlan(
                placeRows: matched,
                // Nothing of yours matched: the nearby venues ARE the answer.
                // Something did: a few more nearby still help ("Deli" should
                // show the other delis, not only the one you saved), but the
                // list stays short so your own places lead.
                suggestedRows: min(max(suggestedPlaces, 0), matched == 0 ? maxSuggestedRows : maxExtraSuggestedRows),
                peopleRows: 0,
                filtersMap: true
            )
        }
    }

    /// "SUGGESTED NEARBY" when it is all there is, "MORE NEARBY" under your own matches.
    var suggestedHeader: String { placeRows == 0 ? "SUGGESTED NEARBY" : "MORE NEARBY" }

    var placesHeader: String { "PLACES" }

    /// The sheet's handle line: "26 places · 3 nearby", "6 nearby", "2 people".
    var handleTitle: String {
        var parts: [String] = []
        if placeRows > 0 { parts.append(placeRows == 1 ? "1 place" : "\(placeRows) places") }
        if suggestedRows > 0 { parts.append("\(suggestedRows) nearby") }
        if peopleRows > 0 { parts.append(peopleRows == 1 ? "1 person" : "\(peopleRows) people") }
        return parts.isEmpty ? "No matches" : parts.joined(separator: " · ")
    }
}
