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
/// Which kind of result the sheet is narrowed to — the handle's chips
/// (All | Places 26 | People 2 | Nearby 6), Wes 2026-10-29.
enum HomeSearchScope: Int, CaseIterable {
    case all, places, people, nearby, widgets
}

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
    /// The chip in effect, and how many of each kind exist (the chips and
    /// headers count these; All shows a short list of some kinds)
    var scope: HomeSearchScope = .all
    var placesTotal: Int = 0
    var peopleTotal: Int = 0
    var suggestedTotal: Int = 0
    var widgetsTotal: Int = 0

    static let maxWidgetRows = 3
    static let maxSuggestedRows = 6
    /// When your own places already match, nearby venues are extras.
    static let maxExtraSuggestedRows = 3
    static let maxPeopleRows = 6
    static let maxRecentRows = 5

    var statusRows: Int { status == nil ? 0 : 1 }
    var isIdle: Bool { recentRows + browseRows > 0 }

    /// "Show all N" closes a section that All cut short; tapping it picks that chip
    var morePeople: Bool { scope == .all && peopleTotal > peopleRows }
    var moreNearby: Bool { scope == .all && suggestedTotal > suggestedRows }
    /// Table rows per section, the "Show all" row included
    var peopleSectionRows: Int { peopleRows + (morePeople ? 1 : 0) }
    var suggestedSectionRows: Int { suggestedRows + (moreNearby ? 1 : 0) }

    var hasRows: Bool {
        widgetRows + placeRows + suggestedRows + peopleRows + statusRows + recentRows + browseRows > 0
    }

    /// Does the query have anything to show besides the status line?
    var hasResults: Bool { widgetRows + placeRows + suggestedRows + peopleRows > 0 }

    /// The pins narrow with the query only when a place matched. A query that
    /// only names a person ("Nick") leaves the map as it was instead of
    /// emptying it — the person is in PEOPLE.
    var filtersMap: Bool { placesTotal > 0 }

    /// - Parameter scope: the chip picked; a chip whose kind has no results
    ///   falls back to All (the query moved on and emptied it).
    static func make(matchedPlaces: Int,
                     suggestedPlaces: Int,
                     people: Int,
                     widgets: Int = 0,
                     status: HomeSearchStatus? = nil,
                     scope requested: HomeSearchScope = .all) -> HomeSearchPlan {
        let places = max(matchedPlaces, 0)
        let peopleCount = max(people, 0)
        let nearby = max(suggestedPlaces, 0)
        let widgetCount = min(max(widgets, 0), maxWidgetRows)
        let total: [HomeSearchScope: Int] = [.places: places, .people: peopleCount, .nearby: nearby, .widgets: widgetCount]
        let scope = (requested == .all || (total[requested] ?? 0) == 0) ? .all : requested

        var plan = HomeSearchPlan(placeRows: 0, suggestedRows: 0, peopleRows: 0, status: status, scope: scope,
                                  placesTotal: places, peopleTotal: peopleCount,
                                  suggestedTotal: nearby, widgetsTotal: widgetCount)
        switch scope {
        case .all:
            plan.placeRows = places
            // Nothing of yours matched: the nearby venues ARE the answer.
            // Something did: a few more nearby still help ("Deli" should
            // show the other delis), but your own places lead.
            plan.suggestedRows = min(nearby, places == 0 ? maxSuggestedRows : maxExtraSuggestedRows)
            plan.peopleRows = min(peopleCount, maxPeopleRows)
            plan.widgetRows = widgetCount
        case .places: plan.placeRows = places
        case .people: plan.peopleRows = peopleCount
        case .nearby: plan.suggestedRows = nearby
        case .widgets: plan.widgetRows = widgetCount
        }
        return plan
    }

    /// The sheet under a focused, empty bar: recent searches, then browse chips.
    static func idle(recent: Int, browse: Int = HomeSearchBrowseItem.all.count) -> HomeSearchPlan {
        HomeSearchPlan(placeRows: 0, suggestedRows: 0, peopleRows: 0,
                       recentRows: min(max(recent, 0), maxRecentRows),
                       browseRows: max(browse, 0))
    }

    // Section headers count everything of their kind: "PLACES (26)"
    var placesHeader: String { "PLACES (\(placesTotal))" }
    var peopleHeader: String { "PEOPLE (\(peopleTotal))" }
    var suggestedHeader: String { "NEARBY (\(suggestedTotal))" }
    var widgetsHeader: String { "WIDGETS (\(widgetsTotal))" }

    /// The handle's chips — only when there is more than one kind to pick
    /// between; one kind needs no filter (the handle line says it instead).
    var scopeChips: [HomeSearchScope] {
        guard !isIdle else { return [] }
        let kinds = HomeSearchScope.allCases.filter { $0 != .all && total(of: $0) > 0 }
        return kinds.count >= 2 ? [.all] + kinds : []
    }

    func total(of scope: HomeSearchScope) -> Int {
        switch scope {
        case .all: return placesTotal + peopleTotal + suggestedTotal + widgetsTotal
        case .places: return placesTotal
        case .people: return peopleTotal
        case .nearby: return suggestedTotal
        case .widgets: return widgetsTotal
        }
    }

    func chipTitle(_ scope: HomeSearchScope) -> String {
        switch scope {
        case .all: return "All"
        case .places: return "Places \(placesTotal)"
        case .people: return "People \(peopleTotal)"
        case .nearby: return "Nearby \(suggestedTotal)"
        case .widgets: return "Widgets \(widgetsTotal)"
        }
    }

    /// The sheet's handle line when there are no chips: "Places 26",
    /// "Searching…", "Recent searches".
    var handleTitle: String {
        if isIdle { return recentRows > 0 ? "Recent searches" : "Browse nearby" }
        let parts = HomeSearchScope.allCases.filter { $0 != .all && total(of: $0) > 0 }.map(chipTitle)
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
