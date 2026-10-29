import Foundation

/// The home search bar's prompt. One search covers everything — places
/// (yours, your network's, nearby), people and widgets — in one sheet, with
/// a count on each section (Wes, 2026-10-29: the Places/People toggle is gone).
enum HomeSearchCopy {
    static let placeholder = "Search anything"   // places, people and widgets (Wes, 2026-10-08)
}

/// What the remote lookups are doing for the current query — shown as one
/// quiet row under the results instead of silence (offline used to look
/// exactly like "no results").
enum HomeSearchStatus: Equatable {
    /// Lookups are still out
    case searching
    /// No connection: only places saved on this phone can match
    case offline
    /// A lookup failed for another reason; tap to retry
    case failed

    var text: String {
        switch self {
        case .searching: return "Searching nearby…"
        case .offline: return "You're offline. Showing places saved on this phone."
        case .failed: return "Nearby results didn't load. Tap to try again."
        }
    }
}

/// A one-tap search under an empty, focused bar ("Coffee", "Bars"): the word
/// runs through every channel, including the server's category path.
struct HomeSearchBrowseItem: Equatable {
    let title: String
    let query: String
    let symbolName: String

    static let all: [HomeSearchBrowseItem] = [
        .init(title: "Coffee", query: "coffee", symbolName: "cup.and.saucer.fill"),
        .init(title: "Food", query: "food", symbolName: "fork.knife"),
        .init(title: "Bars", query: "bars", symbolName: "wineglass.fill"),
        .init(title: "Shopping", query: "shopping", symbolName: "bag.fill"),
        .init(title: "Outdoors", query: "outdoor", symbolName: "leaf.fill"),
        .init(title: "Fitness", query: "fitness", symbolName: "figure.run")
    ]
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
    /// Widgets whose name matches ("postcard" → Postcard), at the top
    /// (Wes, 2026-10-08)
    var widgetRows: Int = 0
    /// The lookup status line (searching / offline / failed), at the bottom
    var status: HomeSearchStatus? = nil
    /// Focused bar, nothing typed: recent searches and browse chips
    var recentRows: Int = 0
    var browseRows: Int = 0

    static let maxWidgetRows = 3
    static let maxSuggestedRows = 6
    /// When your own places already match, nearby venues are extras.
    static let maxExtraSuggestedRows = 3
    static let maxPeopleRows = 6
    static let maxRecentRows = 5

    var statusRows: Int { status == nil ? 0 : 1 }
    var isIdle: Bool { recentRows + browseRows > 0 }

    var hasRows: Bool {
        widgetRows + placeRows + suggestedRows + peopleRows + statusRows + recentRows + browseRows > 0
    }

    /// Does the query have anything to show besides the status line?
    var hasResults: Bool { widgetRows + placeRows + suggestedRows + peopleRows > 0 }

    /// The pins narrow with the query only when a place matched. A query that
    /// only names a person ("Nick") leaves the map as it was instead of
    /// emptying it — the person is in PEOPLE.
    var filtersMap: Bool { placeRows > 0 }

    static func make(matchedPlaces: Int,
                     suggestedPlaces: Int,
                     people: Int,
                     widgets: Int = 0,
                     status: HomeSearchStatus? = nil) -> HomeSearchPlan {
        let matched = max(matchedPlaces, 0)
        return HomeSearchPlan(
            placeRows: matched,
            // Nothing of yours matched: the nearby venues ARE the answer.
            // Something did: a few more nearby still help ("Deli" should
            // show the other delis, not only the one you saved), but the
            // list stays short so your own places lead.
            suggestedRows: min(max(suggestedPlaces, 0), matched == 0 ? maxSuggestedRows : maxExtraSuggestedRows),
            peopleRows: min(max(people, 0), maxPeopleRows),
            widgetRows: min(max(widgets, 0), maxWidgetRows),
            status: status
        )
    }

    /// The sheet under a focused, empty bar: recent searches, then browse chips.
    static func idle(recent: Int, browse: Int = HomeSearchBrowseItem.all.count) -> HomeSearchPlan {
        HomeSearchPlan(placeRows: 0, suggestedRows: 0, peopleRows: 0,
                       recentRows: min(max(recent, 0), maxRecentRows),
                       browseRows: max(browse, 0))
    }

    // Section headers carry their counts: "PLACES (26)", "PEOPLE (2)", "NEARBY (6)"
    var placesHeader: String { "PLACES (\(placeRows))" }
    var peopleHeader: String { "PEOPLE (\(peopleRows))" }
    var suggestedHeader: String { "NEARBY (\(suggestedRows))" }
    var widgetsHeader: String { "WIDGETS (\(widgetRows))" }

    /// The sheet's handle line: "Places 26 | People 2 | Nearby 6".
    var handleTitle: String {
        if isIdle { return recentRows > 0 ? "Recent searches" : "Browse nearby" }
        var parts: [String] = []
        if placeRows > 0 { parts.append("Places \(placeRows)") }
        if peopleRows > 0 { parts.append("People \(peopleRows)") }
        if suggestedRows > 0 { parts.append("Nearby \(suggestedRows)") }
        if widgetRows > 0 { parts.append("Widgets \(widgetRows)") }
        if parts.isEmpty {
            switch status {
            case .searching: return "Searching…"
            case .offline: return "Offline"
            default: return "No matches"
            }
        }
        return parts.joined(separator: " | ")
    }
}
