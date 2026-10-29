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
        case .places: return "Search anything"   // places, people and widgets (Wes, 2026-10-08)
        case .people: return "Search people"
        }
    }
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
    /// People mode leaves the map alone: filtering pins by a person's name
    /// matches place names by accident and empties the map for no reason.
    var filtersMap: Bool
    /// Widgets whose name matches ("postcard" → Postcard), at the top in
    /// Places mode (Wes, 2026-10-08)
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

    static func make(mode: HomeSearchMode,
                     matchedPlaces: Int,
                     suggestedPlaces: Int,
                     people: Int,
                     widgets: Int = 0,
                     status: HomeSearchStatus? = nil) -> HomeSearchPlan {
        switch mode {
        case .people:
            return HomeSearchPlan(
                placeRows: 0,
                suggestedRows: 0,
                peopleRows: min(max(people, 0), maxPeopleRows),
                filtersMap: false,
                status: status
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
                filtersMap: true,
                widgetRows: min(max(widgets, 0), maxWidgetRows),
                status: status
            )
        }
    }

    /// The sheet under a focused, empty bar: recent searches, then browse
    /// chips (Places mode only; People has nothing to browse).
    static func idle(mode: HomeSearchMode, recent: Int, browse: Int = HomeSearchBrowseItem.all.count) -> HomeSearchPlan {
        HomeSearchPlan(placeRows: 0, suggestedRows: 0, peopleRows: 0, filtersMap: false,
                       recentRows: min(max(recent, 0), maxRecentRows),
                       browseRows: mode == .places ? max(browse, 0) : 0)
    }

    /// "SUGGESTED NEARBY" when it is all there is, "MORE NEARBY" under your own matches.
    var suggestedHeader: String { placeRows == 0 ? "SUGGESTED NEARBY" : "MORE NEARBY" }

    var placesHeader: String { "PLACES" }

    /// The sheet's handle line: "26 places · 3 nearby", "6 nearby", "2 people".
    var handleTitle: String {
        if isIdle { return recentRows > 0 ? "Recent searches" : "Browse nearby" }
        var parts: [String] = []
        if widgetRows > 0 { parts.append(widgetRows == 1 ? "1 widget" : "\(widgetRows) widgets") }
        if placeRows > 0 { parts.append(placeRows == 1 ? "1 place" : "\(placeRows) places") }
        if suggestedRows > 0 { parts.append("\(suggestedRows) nearby") }
        if peopleRows > 0 { parts.append(peopleRows == 1 ? "1 person" : "\(peopleRows) people") }
        if parts.isEmpty {
            switch status {
            case .searching: return "Searching…"
            case .offline: return "Offline"
            default: return "No matches"
            }
        }
        return parts.joined(separator: " · ")
    }
}
