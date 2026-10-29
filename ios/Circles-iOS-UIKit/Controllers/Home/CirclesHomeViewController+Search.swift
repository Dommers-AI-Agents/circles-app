import UIKit
import FavWidgets
import FavWidgetsCore
import MapKit
import CoreLocation

// The home search bar: the delegate, the local match, and the remote lookups.
//
// One keystroke matches locally at once (your places, the network's, and
// whatever is on the map — the same corpus the pins use), then ONE debounce
// asks the remote channels the current mode shows: the network's saves, the
// catalog and Apple Maps for Places; people for People. Answers are cached per
// (channel, query, origin cell) so backspacing or flipping the mode costs
// nothing, superseded requests are cancelled, and a status line says when
// lookups are still out or failed (offline used to look like "no results").

// MARK: - UISearchBarDelegate
extension CirclesHomeViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Editing the query brings the results list back after a map peek
        isSearchSheetCollapsed = false

        guard !trimmed.isEmpty else {
            endSearch(keepFocus: true)
            return
        }

        isSearching = true
        enterSearchLayout()
        matchedWidgetsCache = searchMode == .places
            ? WidgetSearchMatcher.matches(trimmed, in: FavWidgetRegistry.descriptors, limit: HomeSearchPlan.maxWidgetRows)
            : []

        // Apple answers by meaning ("deli" finds delis), so they can't be
        // re-filtered by text: keep them while the query only grows
        // ("bak" → "bake"), drop them when it changes direction.
        if !trimmed.lowercased().hasPrefix(state.lastAppleQuery.lowercased()) || state.lastAppleQuery.isEmpty {
            appleCandidates = []
        }
        // People already on screen stay if they still match — no flicker
        // between keystrokes while the new answer is on its way.
        searchedUsers = searchedUsers.filter { Self.userMatches($0, query: trimmed) }

        filterPlaces(searchText: trimmed)
        applySearchFilterToMap(trimmed)
        scheduleRemoteSearch(for: trimmed)

        refreshSearchOverlay()
        updateEmptyState()
    }

    /// The query a person's name must contain, word by word.
    static func userMatches(_ user: User, query: String) -> Bool {
        let name = PlaceSearchText.fold([user.displayName, user.firstName ?? "", user.lastName ?? ""].joined(separator: " "))
        return PlaceSearchText.fold(query).split(separator: " ").allSatisfy { name.contains($0) }
    }

    /// What the dropdown should show right now. Everything that draws or sizes
    /// the overlay asks this, so the sections can never disagree about how
    /// many rows exist.
    var searchPlan: HomeSearchPlan {
        if !isSearching {
            // Focused, nothing typed: recent searches and browse chips
            guard searchBar.isFirstResponder else {
                return HomeSearchPlan.make(mode: searchMode, matchedPlaces: 0, suggestedPlaces: 0, people: 0)
            }
            return HomeSearchPlan.idle(mode: searchMode, recent: recentSearches.list.queries.count)
        }
        return HomeSearchPlan.make(
            mode: searchMode,
            matchedPlaces: filteredPlaces.count,
            suggestedPlaces: suggestedRows.count,
            people: searchedUsers.count,
            widgets: matchedWidgetsCache.count,
            status: state.searchStatus
        )
    }

    /// Widgets the query names ("postcard" → Postcard), every widget the
    /// app has whether or not it's turned on in the tab
    var matchedWidgets: [FavWidgetDescriptor] {
        isSearching ? matchedWidgetsCache : []
    }

    /// Recent searches shown under the empty bar
    var visibleRecentSearches: [String] {
        Array(recentSearches.list.queries.prefix(searchPlan.recentRows))
    }

    /// Switching between Places and People re-runs the current query under the
    /// new rules — answers already fetched come from the cache.
    @objc func searchModeControlChanged() {
        guard let mode = HomeSearchMode(rawValue: searchModeControl.selectedSegmentIndex) else { return }
        searchModeChanged(to: mode)
    }

    func searchModeChanged(to mode: HomeSearchMode) {
        searchMode = mode
        searchBar.placeholder = mode.placeholder
        isSearchSheetCollapsed = false
        let trimmed = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            mapViewController?.setSearchFilter(nil)
            refreshSearchOverlay()
            return
        }
        searchBar(searchBar, textDidChange: trimmed)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // Same as the Done button: keyboard down, the list stays open (Wes).
        recordRecentSearch()
        searchBar.resignFirstResponder()
        updateEmptyState()
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        refreshSearchOriginIfStale()
        // The search layout from the first tap, not the first keystroke: the
        // Places/People control used to sit over the avatar row until a
        // letter was typed (Wes, 2026-10-09)
        enterSearchLayout()
        searchBar.setShowsCancelButton(true, animated: true)
        // Refocusing a collapsed sheet expands it again
        expandSearchSheet()
        // Nothing typed yet: recent searches and browse chips
        if !isSearching { refreshSearchOverlay() }
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
        // Left the bar with nothing typed: the search is over, so the
        // Places/People control goes too (Wes, 2026-10-08: it stayed up over
        // the Widgets tab). A real query keeps it — the results are still up.
        if (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resetSearch()
        }
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        resetSearch()
    }

    /// Back to no search at all: empty bar, keyboard down, places mode,
    /// results gone, the map unfiltered. Cancel does this, and so does the
    /// Home tab — arriving "home" and finding last week's search still
    /// filtering the map is a bug, not a memory.
    func resetSearch() {
        setSearchModeControlVisible(false)
        searchMode = .places
        searchModeControl.selectedSegmentIndex = HomeSearchMode.places.rawValue
        searchBar.placeholder = HomeSearchMode.places.placeholder
        searchBar.text = ""
        searchBar.resignFirstResponder()
        endSearch(keepFocus: false)
    }

    /// The one teardown every exit uses (empty text, Cancel, a person or a
    /// nearby venue tapped): lookups cancelled, search state back to rest,
    /// the map's filter and the network hits' extra pins gone.
    func endSearch(keepFocus: Bool) {
        let hadNetworkHits = !state.networkSearchHits.isEmpty
        cancelRemoteSearch()
        state.clearSearch()
        matchedWidgetsCache = []
        mapViewController?.setSearchFilter(nil)
        if hadNetworkHits { refreshMapDisplay(adjustRegion: false) }
        if keepFocus && searchBar.isFirstResponder {
            refreshSearchOverlay()   // recent searches + browse
        } else {
            hideSearchResults()
        }
        updateEmptyState()
    }

    /// Runs a recent search or a browse chip as if typed.
    func runSearch(_ query: String) {
        searchBar.text = query
        searchBar(searchBar, textDidChange: query)
    }

    /// The bar's text as a recent search (a result was tapped, or Search).
    func recordRecentSearch() {
        let text = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        recentSearches.record(text)
    }
}

// MARK: - Local match
extension CirclesHomeViewController {
    /// The places the search matches against and the pins show while it is
    /// up (HomeState.searchCorpus): built once per change of the places or
    /// the map's people/category filter.
    func searchCorpus() -> (places: [Place], index: SavedPlaceIndex) {
        state.searchCorpus(context: placeFilterContext())
    }

    /// Matches the corpus against the text and rebuilds the nearby rows. No
    /// network: the remote lookups are scheduled by the keystroke itself
    /// (scheduleRemoteSearch), and an answer arriving only re-runs this.
    func filterPlaces(searchText: String) {
        let interval = Signposts.search.begin("filterPlaces")
        defer { Signposts.search.end(interval) }
        let corpus = searchCorpus()

        // Shared matcher (Place.matches) — the same predicate filters the map
        // pins, so this list and the pins can't drift. Apple Maps may have
        // recognised a saved "restaurant" as the deli being asked for; those
        // ids ride along to the pins too (setSearchFilter(_:matchedPlaceIds:)).
        let split = POIDuplicateMatcher.partition(candidates: appleCandidates, index: corpus.index)
        appleMatchedPlaceIds = Set(split.matched.map(\.id))
        appleVenues = split.unsaved
        let matched = corpus.places.filter { appleMatchedPlaceIds.contains($0.id) || $0.matches(searchQuery: searchText) }
        // One row per real-world venue, however many people saved it (the
        // same collapse the map's list uses).
        let deduped = Place.dedupedByVenue(matched, preferredOwnerId: AuthService.shared.getUserId() ?? "")

        // Nearest first, with the distance shown on each row ("looking for
        // pizza NEAR ME" is the whole query).
        let entries = DistancePlaceSorter.sorted(deduped, from: searchReferenceLocation())
        var distances: [String: CLLocationDistance] = [:]
        for entry in entries { if let d = entry.distance { distances[entry.place.id] = d } }
        searchDistances = distances
        filteredPlaces = entries.map(\.place)

        rebuildSuggestedRows(index: corpus.index)
    }

    /// The pins narrow with the text (the map debounces internally, camera
    /// stays), but only in Places mode — filtering the map by a person's name
    /// matches place names by accident and empties it for nothing.
    func applySearchFilterToMap(_ query: String) {
        mapViewController?.setSearchFilter(searchMode.filtersMap(query),
                                           matchedPlaceIds: searchMode == .places ? appleMatchedPlaceIds : [])
    }

    /// The search text currently filtering the home surface, or nil — the
    /// expand handoff seeds the modal's search bar with this.
    var activeSearchQuery: String? {
        guard isSearching else { return nil }
        let trimmed = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// The point "near" means. Resolved by SearchOriginResolver from every
    /// position the phone or the server knows; the map's centre only when
    /// there is nothing else (it is the pin-fitted region, not where you are).
    func searchReferenceLocation() -> CLLocation? {
        resolvedSearchOrigin()?.location
    }

    func resolvedSearchOrigin() -> SearchOriginResolver.Resolution? {
        var candidates: [SearchOriginResolver.Candidate] = []
        if let fix = LocationService.shared.lastKnownLocation { candidates.append(.init(location: fix, source: .serviceFix)) }
        if let fix = mapViewController?.currentUserLocation { candidates.append(.init(location: fix, source: .osCachedFix)) }
        if let fix = LocationService.shared.persistedFix { candidates.append(.init(location: fix, source: .persistedFix)) }
        if let known = AuthService.shared.currentUser?.lastKnownLocation { candidates.append(.init(location: known.location, source: .serverLastKnown)) }
        if let assumed = AuthService.shared.currentUser?.assumedLocation { candidates.append(.init(location: assumed.location, source: .serverAssumed)) }
        if let map = mapViewController {
            let centre = map.currentRegion.center
            candidates.append(.init(location: CLLocation(latitude: centre.latitude, longitude: centre.longitude), source: .mapRegion))
        }
        return SearchOriginResolver.resolve(candidates)
    }

    /// A fresh fix is worth a short wait, but the list never waits for it:
    /// results render from the best cached origin, and re-sort (and re-ask
    /// the nearby channels) only if the real position is somewhere else.
    func refreshSearchOriginIfStale() {
        let current = resolvedSearchOrigin()
        let freshEnough = current?.source == .serviceFix
            && Date().timeIntervalSince(current!.location.timestamp) < 5 * 60
        guard !freshEnough else { return }
        LocationService.shared.getCurrentLocation(timeout: 3) { [weak self] fix in
            guard let self, let fix, self.isSearching else { return }
            if let before = current?.location, before.distance(from: fix) < 500 { return }
            DispatchQueue.main.async {
                let text = self.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { return }
                self.filterPlaces(searchText: text)
                self.scheduleRemoteSearch(for: text)
                self.refreshSearchOverlay()
            }
        }
    }

    /// The nearby rows on show: all of them when nothing of yours matched, a
    /// few under your own matches (HomeSearchPlan decides how many).
    var visibleSuggestedRows: [SuggestedRow] {
        Array(suggestedRows.prefix(searchPlan.suggestedRows))
    }

    /// Recomputes the nearby section from both channels.
    func rebuildSuggestedRows(index: SavedPlaceIndex? = nil) {
        let savedIndex = index ?? searchCorpus().index
        let merged = SuggestedNearbyMerger.merge(global: suggestedPlaces, apple: appleVenues,
                                                 savedIndex: savedIndex, from: searchReferenceLocation())
        suggestedRows = merged.map(\.row)
        var distances: [String: CLLocationDistance] = [:]
        for entry in merged { if let d = entry.distance { distances[entry.row.id] = d } }
        suggestedDistances = distances
    }

    /// The matched places that get a row (all of them, nearest first).
    var visibleFilteredPlaces: [Place] {
        Array(filteredPlaces.prefix(searchPlan.placeRows))
    }
}

// MARK: - Remote channels
extension CirclesHomeViewController {
    /// Cancels every lookup still out and ends the debounce generation.
    func cancelRemoteSearch() {
        searchDebouncer.cancel()
        searchRequests.values.forEach { $0.cancel() }
        searchRequests.removeAll()
        venueSearch.cancelVenueSearch()
    }

    /// Asks the channels the current mode shows, after one debounce. Cached
    /// answers apply at once and skip the network.
    func scheduleRemoteSearch(for query: String, bypassCache: Bool = false) {
        searchRequests.values.forEach { $0.cancel() }
        searchRequests.removeAll()
        state.pendingSearchChannels = []
        state.failedSearchChannels = []
        state.searchFailedOffline = false

        guard SearchDebouncer.isServerEligible(query) else {
            searchDebouncer.cancel()
            return
        }
        // No reference point → skip the nearby channels: quality-ranked global
        // hits with no geo filter would confidently suggest pizza on another
        // continent. The network's saves still match by name.
        let reference = searchReferenceLocation()
        let origin = reference?.coordinate
        let caches = state.searchCaches

        var channels: [HomeSearchChannel] = []
        switch searchMode {
        case .people:
            channels = [.people]
        case .places:
            channels = [.network]
            if reference != nil {
                channels.append(.catalog)
                if query.count >= 3 { channels.append(.apple) }   // NearbyPlaceSearch's own minimum
            }
        }

        // Serve what the cache has; ask for the rest
        var toFetch: [HomeSearchChannel] = []
        for channel in channels {
            if !bypassCache, applyCached(channel, query: query, origin: origin, caches: caches) { continue }
            toFetch.append(channel)
        }
        guard !toFetch.isEmpty else {
            searchDebouncer.cancel()
            return
        }
        state.pendingSearchChannels = Set(toFetch)

        searchDebouncer.schedule { [weak self] generation in
            guard let self else { return }
            for channel in toFetch {
                self.fetch(channel, query: query, reference: reference, generation: generation)
            }
        }
    }

    /// Applies a cached answer for `channel`; false when there is none.
    private func applyCached(_ channel: HomeSearchChannel, query: String,
                             origin: CLLocationCoordinate2D?, caches: HomeSearchCaches) -> Bool {
        switch channel {
        case .people:
            guard let users = caches.people.value(for: .init(channel: "people", query: query, origin: nil)) else { return false }
            searchedUsers = users
        case .network:
            guard let places = caches.network.value(for: .init(channel: "network", query: query, origin: origin)) else { return false }
            state.networkSearchHits = places
            filterPlaces(searchText: query)
            refreshMapDisplay(adjustRegion: false)
        case .catalog:
            guard let places = caches.catalog.value(for: .init(channel: "catalog", query: query, origin: origin)) else { return false }
            suggestedPlaces = places
            rebuildSuggestedRows()
        case .apple:
            guard let venues = caches.apple.value(for: .init(channel: "apple", query: query, origin: origin)) else { return false }
            state.lastAppleQuery = query
            appleCandidates = venues
            filterPlaces(searchText: query)
            applySearchFilterToMap(query)
        }
        return true
    }

    private func fetch(_ channel: HomeSearchChannel, query: String, reference: CLLocation?, generation: Int) {
        let origin = reference?.coordinate
        let caches = state.searchCaches
        switch channel {
        case .people:
            searchRequests[.people] = UserService.shared.searchUsers(query: query) { [weak self] result in
                DispatchQueue.main.async {
                    self?.finish(.people, generation: generation, result: result.map { Array($0.prefix(12)) }) { users in
                        caches.people.store(users, for: .init(channel: "people", query: query, origin: nil))
                        self?.searchedUsers = users
                    }
                }
            }
        case .network:
            searchRequests[.network] = PlaceService.shared.searchNetworkPlaces(query: query, near: reference) { [weak self] result in
                DispatchQueue.main.async {
                    self?.finish(.network, generation: generation, result: result) { places in
                        caches.network.store(places, for: .init(channel: "network", query: query, origin: origin))
                        guard let self else { return }
                        self.state.networkSearchHits = places
                        self.filterPlaces(searchText: query)
                        // New hits get their pins (the map reads the same corpus)
                        self.refreshMapDisplay(adjustRegion: false)
                        self.applySearchFilterToMap(query)
                    }
                }
            }
        case .catalog:
            guard let reference else { return }
            fetchCatalog(serverQuery: query, typedQuery: query, reference: reference,
                         generation: generation, allowFallback: true)
        case .apple:
            guard let reference else { return }
            venueSearch.searchVenues(query: query, near: reference) { [weak self] result in
                guard let self, self.searchDebouncer.isCurrent(generation) else { return }
                self.state.pendingSearchChannels.remove(.apple)
                // Throttled or offline: Apple's channel is silently nothing
                if case .success(let venues) = result {
                    caches.apple.store(venues, for: .init(channel: "apple", query: query, origin: reference.coordinate))
                    self.state.lastAppleQuery = query
                    self.appleCandidates = venues
                    self.filterPlaces(searchText: query)
                    self.applySearchFilterToMap(query)
                }
                self.refreshSearchOverlay()
                self.updateEmptyState()
            }
        }
    }

    /// The server matches exact name-word PREFIXES, so a typo ("piza")
    /// returns nothing even though the local sections forgive it — when the
    /// full query comes back empty, retry ONCE with a 3-char prefix of the
    /// longest word ("piz" does match pizza-named venues).
    private func fetchCatalog(serverQuery: String, typedQuery: String, reference: CLLocation,
                              generation: Int, allowFallback: Bool) {
        let caches = state.searchCaches
        searchRequests[.catalog] = GlobalPlaceService.shared.searchGlobalPlaces(
            query: serverQuery,
            location: (lat: reference.coordinate.latitude, lng: reference.coordinate.longitude),
            radius: 80,
            limit: 50
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.searchDebouncer.isCurrent(generation) else { return }
                if case .success(let places) = result, places.isEmpty, allowFallback,
                   let longest = typedQuery.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                       .max(by: { $0.count < $1.count }),
                   longest.count >= 4 {
                    self.fetchCatalog(serverQuery: String(longest.prefix(3)), typedQuery: typedQuery,
                                      reference: reference, generation: generation, allowFallback: false)
                    return
                }
                self.finish(.catalog, generation: generation, result: result.map { Array($0.prefix(8)) }) { places in
                    caches.catalog.store(places, for: .init(channel: "catalog", query: typedQuery, origin: reference.coordinate))
                    self.suggestedPlaces = places
                    self.rebuildSuggestedRows()
                }
            }
        }
    }

    /// One answer in: stale ones (an older generation) are dropped; a failure
    /// marks the channel for the status line; then the sheet redraws.
    private func finish<T>(_ channel: HomeSearchChannel, generation: Int, result: Result<T, Error>,
                           apply: (T) -> Void) {
        guard searchDebouncer.isCurrent(generation), isSearching else { return }
        searchRequests[channel] = nil
        state.pendingSearchChannels.remove(channel)
        switch result {
        case .success(let value):
            apply(value)
        case .failure(let error):
            state.failedSearchChannels.insert(channel)
            if case .noInternet? = error as? APIError { state.searchFailedOffline = true }
            Logger.debug("🔎 \(channel) lookup failed: \(error)")
        }
        refreshSearchOverlay()
        updateEmptyState()
    }

    /// The status row was tapped after a failure: ask again, past the cache.
    func retryFailedSearch() {
        let text = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        scheduleRemoteSearch(for: text, bypassCache: true)
        refreshSearchOverlay()
    }
}

// MARK: - Results actions
extension CirclesHomeViewController {
    /// The 'i' accessory: peek at a place in a sheet WITHOUT tearing down the
    /// search — dismiss and the results are still there.
    func presentSearchPreview(place: Place, circle: Circle?) {
        searchBar.resignFirstResponder()
        let detailVC = PlaceDetailViewController(place: place, circle: circle)
        let nav = UINavigationController(rootViewController: detailVC)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    /// Handles a tap on a PEOPLE result: connections/followees filter the map
    /// (like tapping their avatar); everyone else opens their profile to act.
    func selectSearchedUser(_ user: User) {
        recordRecentSearch()
        searchBar.text = ""
        searchBar.resignFirstResponder()
        endSearch(keepFocus: false)

        let isConnected = user.connectionStatus == "connected" || user.connectionStatus == "accepted"
        let isFollowing = user.isFollowing == true
        if isConnected || isFollowing {
            selectConnection(id: user.id, user: user)
        } else {
            let profileVC = ProfileViewController()
            profileVC.configureWith(user: user)
            navigationController?.pushViewController(profileVC, animated: true)
        }
    }

    /// The matched part of `text` in bold, for a result row.
    func highlighted(_ text: String, query: String, font: UIFont = .systemFont(ofSize: 17)) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text, attributes: [.font: font])
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        let bold = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        for word in words {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                out.addAttribute(.font, value: bold, range: NSRange(range, in: text))
                searchRange = range.upperBound..<text.endIndex
            }
        }
        return out
    }
}
