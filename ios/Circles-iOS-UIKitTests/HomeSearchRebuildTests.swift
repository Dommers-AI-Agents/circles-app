import Testing
import Foundation
import CoreLocation
@testable import Circles_iOS

// The home search rebuild (2026-10-29): one debounce with generations, a
// per-query answer cache, recent searches, a keyed saved-place index, the
// memoized search text, and one corpus for the results list AND the pins.

private func makePlace(_ id: String, name: String? = nil, lat: Double? = nil, lng: Double? = nil,
                       circle: String? = "mine", addedBy: String = "me", tags: [String]? = nil) -> Place {
    let location = (lat != nil && lng != nil) ? GeoLocation(type: "Point", coordinates: [lng!, lat!]) : nil
    return Place(id: id, name: name ?? id, description: nil, address: "", location: location, website: nil, phone: nil,
                 googlePlaceId: nil, photos: nil, videos: nil, category: .restaurant, customCategoryId: nil,
                 subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
                 publicNotes: nil, tags: tags, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
                 likesCount: nil, commentsCount: nil, circleId: circle, addedBy: addedBy, addedByUser: nil,
                 privacy: .public, createdAt: Date(), updatedAt: Date())
}

struct SearchDebouncerTests {
    /// Collects scheduled work instead of waiting on the clock
    final class ManualClock {
        var items: [DispatchWorkItem] = []
        lazy var scheduler: SearchDebouncer.Scheduler = { [unowned self] _, item in self.items.append(item) }
        func runAll() { items.forEach { $0.perform() }; items.removeAll() }
    }

    @Test func onlyTheLatestGenerationRuns() {
        let clock = ManualClock()
        let debouncer = SearchDebouncer(delay: 0.3, scheduler: clock.scheduler)
        var ran: [Int] = []
        debouncer.schedule { ran.append($0) }
        debouncer.schedule { ran.append($0) }
        let last = debouncer.schedule { ran.append($0) }
        clock.runAll()
        #expect(ran == [last])
        #expect(debouncer.isCurrent(last))
    }

    @Test func cancelMakesInFlightAnswersStale() {
        let clock = ManualClock()
        let debouncer = SearchDebouncer(scheduler: clock.scheduler)
        var ran = false
        let generation = debouncer.schedule { _ in ran = true }
        debouncer.cancel()
        clock.runAll()
        #expect(!ran)
        #expect(!debouncer.isCurrent(generation))
    }

    @Test func oneLetterNeverGoesToTheServer() {
        #expect(!SearchDebouncer.isServerEligible("p"))
        #expect(!SearchDebouncer.isServerEligible("  p "))
        #expect(SearchDebouncer.isServerEligible("pi"))
    }
}

struct SearchResultCacheTests {
    private let here = CLLocationCoordinate2D(latitude: 35.2271, longitude: -80.8431)

    @Test func sameQueryNearbySameCellIsAHit() {
        let cache = SearchResultCache<[String]>()
        cache.store(["a"], for: .init(channel: "network", query: "Bakery ", origin: here))
        let acrossTheStreet = CLLocationCoordinate2D(latitude: here.latitude + 0.0001, longitude: here.longitude)
        #expect(cache.value(for: .init(channel: "network", query: "bakery", origin: acrossTheStreet)) == ["a"])
        #expect(cache.value(for: .init(channel: "catalog", query: "bakery", origin: here)) == nil)
        let otherTown = CLLocationCoordinate2D(latitude: here.latitude + 0.5, longitude: here.longitude)
        #expect(cache.value(for: .init(channel: "network", query: "bakery", origin: otherTown)) == nil)
    }

    @Test func entriesExpireAndTheOldestIsEvicted() {
        var now = Date(timeIntervalSince1970: 1_000)
        let cache = SearchResultCache<Int>(capacity: 2, ttl: 60, now: { now })
        cache.store(1, for: .init(channel: "c", query: "a", origin: nil))
        cache.store(2, for: .init(channel: "c", query: "b", origin: nil))
        _ = cache.value(for: .init(channel: "c", query: "a", origin: nil))   // "a" is now most recent
        cache.store(3, for: .init(channel: "c", query: "c", origin: nil))
        #expect(cache.value(for: .init(channel: "c", query: "b", origin: nil)) == nil)
        #expect(cache.value(for: .init(channel: "c", query: "a", origin: nil)) == 1)
        now = now.addingTimeInterval(61)
        #expect(cache.value(for: .init(channel: "c", query: "a", origin: nil)) == nil)
        #expect(cache.count == 1)
    }
}

struct RecentSearchListTests {
    @Test func newestFirstNoDuplicatesCapped() {
        var list = RecentSearchList()
        for q in ["pizza", "Tacos", "pizza", "café", "CAFE", "x"] { list = list.adding(q) }
        #expect(list.queries == ["CAFE", "pizza", "Tacos"])
        for i in 0..<20 { list = list.adding("query \(i)") }
        #expect(list.queries.count == RecentSearchList.capacity)
        #expect(list.queries.first == "query 19")
        #expect(list.removing("QUERY 19").queries.first == "query 18")
    }

    @Test func storeIsPerAccount() {
        let defaults = UserDefaults(suiteName: "RecentSearchListTests.\(UUID().uuidString)")!
        var user: String? = "a"
        let store = RecentSearchStore(defaults: defaults, userId: { user })
        store.record("bakery")
        user = "b"
        #expect(store.list.queries.isEmpty)
        store.record("bars")
        user = "a"
        #expect(store.list.queries == ["bakery"])
        user = nil
        store.record("ignored")
        #expect(store.list.queries.isEmpty)
    }
}

struct SavedPlaceIndexTests {
    @Test func sameAnswersAsTheLinearScan() {
        let saved = [
            makePlace("deli", name: "Joe's Deli", lat: 35.2271, lng: -80.8431),
            makePlace("pizza", name: "Pizza Palace", lat: 35.2290, lng: -80.8431),
            makePlace("far", name: "Joe's Deli", lat: 36.0, lng: -80.0),
            makePlace("nowhere", name: "Corner Cafe")
        ]
        let index = SavedPlaceIndex(saved)
        let candidates = [
            makePlace("apple1", name: "Joes Deli", lat: 35.2272, lng: -80.8431),       // same venue, punctuation differs
            makePlace("apple2", name: "Deli Express", lat: 35.2271, lng: -80.8432),    // near + shares "deli"
            makePlace("apple3", name: "Burger Barn", lat: 35.2271, lng: -80.8431),     // near, nothing in common
            makePlace("apple4", name: "Corner Cafe", lat: 10, lng: 10)                 // same name, saved one has no point
        ]
        let fast = POIDuplicateMatcher.partition(candidates: candidates, index: index)
        let slow = POIDuplicateMatcher.partition(candidates: candidates, saved: saved)
        #expect(fast.matched.map(\.id) == slow.matched.map(\.id))
        #expect(fast.unsaved.map(\.id) == slow.unsaved.map(\.id))
        #expect(index.contains(makePlace("x", name: "Corner Cafe")))
        #expect(!index.contains(makePlace("y", name: "Burger Barn", lat: 50, lng: 50)))
    }
}

struct PlaceSearchTextCacheTests {
    @Test func rebuildsOnlyWhenTheSearchableFieldsChange() {
        let cache = PlaceSearchTextCache()
        let before = makePlace("p", name: "Old Name")
        #expect(cache.texts(for: before).exact.contains("old name"))
        #expect(cache.count == 1)
        let renamed = makePlace("p", name: "New Name")
        #expect(cache.texts(for: renamed).exact.contains("new name"))
        let tagged = makePlace("p", name: "New Name", tags: ["date-night"])
        #expect(cache.texts(for: tagged).exact.contains("date night"))
        #expect(cache.count == 1)
    }
}

struct HomeSearchCorpusTests {
    @Test func listAndPinsShareOneCorpusRebuiltOnlyOnChange() {
        let state = HomeState()
        state.userOwnPlaces = [makePlace("own")]
        state.allPlaces = [makePlace("own"), makePlace("viewport", circle: "bobs", addedBy: "bob")]
        var context = HomePlaceFilter.Context(currentUserId: "me")
        context.ownCircleIds = ["mine"]
        context.networkCircleOwners = ["bobs": "bob"]
        context.everyoneAuthorIds = ["me", "bob"]
        let first = state.searchCorpus(context: context)
        #expect(Set(first.places.map(\.id)) == ["own", "viewport"])

        // A network hit for the query joins the same corpus (so it gets a pin)
        state.networkSearchHits = [makePlace("hit", circle: "carls", addedBy: "carl")]
        #expect(Set(state.searchCorpus(context: context).places.map(\.id)) == ["own", "viewport", "hit"])

        // A person selected on the map narrows the hits too
        var bobOnly = context
        bobOnly.selectedConnectionId = "bob"
        #expect(state.searchCorpus(context: bobOnly).places.map(\.id) == ["viewport"])

        // Clearing the search drops the hits again
        state.isSearching = true
        state.clearSearch()
        #expect(state.networkSearchHits.isEmpty)
        #expect(Set(state.searchCorpus(context: context).places.map(\.id)) == ["own", "viewport"])
    }

    @Test func statusLineFollowsTheChannels() {
        let state = HomeState()
        #expect(state.searchStatus == nil)
        state.pendingSearchChannels = [.network, .catalog]
        #expect(state.searchStatus == .searching)
        state.pendingSearchChannels = []
        state.failedSearchChannels = [.network]
        #expect(state.searchStatus == .failed)
        state.searchFailedOffline = true
        #expect(state.searchStatus == .offline)
    }
}

struct HomeSearchPlanIdleAndStatusTests {
    @Test func idleShowsRecentsAndBrowseInPlacesOnly() {
        let places = HomeSearchPlan.idle(mode: .places, recent: 9)
        #expect(places.recentRows == HomeSearchPlan.maxRecentRows)
        #expect(places.browseRows == HomeSearchBrowseItem.all.count)
        #expect(places.handleTitle == "Recent searches")
        let people = HomeSearchPlan.idle(mode: .people, recent: 0)
        #expect(!people.hasRows)
        #expect(HomeSearchPlan.idle(mode: .places, recent: 0).handleTitle == "Browse nearby")
    }

    @Test func statusRowIsARowAndTitlesTheEmptySheet() {
        let searching = HomeSearchPlan.make(mode: .places, matchedPlaces: 0, suggestedPlaces: 0, people: 0, status: .searching)
        #expect(searching.hasRows)
        #expect(!searching.hasResults)
        #expect(searching.handleTitle == "Searching…")
        let offline = HomeSearchPlan.make(mode: .places, matchedPlaces: 2, suggestedPlaces: 0, people: 0, status: .offline)
        #expect(offline.handleTitle == "2 places")
        #expect(SearchSheetLayout.contentHeight(for: offline)
                == SearchSheetLayout.handleHeight + SearchSheetLayout.headerHeight + 3 * SearchSheetLayout.rowHeight)
    }
}
