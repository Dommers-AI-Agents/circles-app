import UIKit
import MapKit
import CoreLocation

// Search-bar delegate, custom place/people search, and PlaceSearchable
// navigation for CirclesHomeViewController. Extracted (Wave 4).

// MARK: - UISearchBarDelegate
extension CirclesHomeViewController: UISearchBarDelegate {
    // Unified search: place matches filter the MAP pins (and its list, when
    // the user opens it) instantly; people are fetched from the server
    // (debounced) and render in the dropdown with the SUGGESTED fallback.
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Editing the query brings the results list back after a map peek
        isSearchSheetCollapsed = false

        guard !trimmed.isEmpty else {
            state.clearSearch()
            userSearchWorkItem?.cancel()
            suggestedSearchWorkItem?.cancel()
            mapViewController?.setSearchFilter(nil)
            hideSearchResults()
            updateEmptyState()
            return
        }

        isSearching = true
        enterSearchLayout()
        if trimmed != lastAppleQuery { appleCandidates = []; lastAppleQuery = trimmed }

        // Places — local, instant. These now render as rows again (capped, see
        // HomeSearchPlan) as well as narrowing the map.
        filterPlaces(searchText: trimmed)

        // The pins narrow with the text (FSM debounces internally, camera
        // stays), but only in Places mode — filtering the map by a person's
        // name matches place names by accident and empties it for nothing.
        mapViewController?.setSearchFilter(searchMode.filtersMap(trimmed), matchedPlaceIds: searchMode == .places ? appleMatchedPlaceIds : [])

        // People — debounced server search so we don't fire a request per
        // keystroke. Clear stale people up front so the PEOPLE section never
        // shows results that don't match the current text (places carry the
        // overlay in the meantime).
        searchedUsers = []
        userSearchWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            UserService.shared.searchUsers(query: trimmed) { result in
                DispatchQueue.main.async {
                    guard let self = self,
                          self.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
                    if case .success(let users) = result {
                        // Cap for a tidy overlay; already excludes the current user server-side
                        self.searchedUsers = Array(users.prefix(12))
                        self.refreshSearchOverlay()
                    }
                }
            }
        }
        userSearchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)

        // Show place matches right away; people fill in when the fetch returns
        refreshSearchOverlay()
        updateEmptyState()
    }

    /// Shows the PEOPLE/SUGGESTED dropdown when either has matches. Place
     /// What the dropdown should show right now. Everything that draws or sizes
    /// the overlay asks this, so the sections can never disagree about how
    /// many rows exist.
    var searchPlan: HomeSearchPlan {
        HomeSearchPlan.make(
            mode: searchMode,
            matchedPlaces: filteredPlaces.count,
            suggestedPlaces: suggestedRows.count,
            people: searchedUsers.count
        )
    }

    /// Switching between Places and People re-runs the current query under the
    /// new rules — including handing the map back when People is chosen.
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
        searchBar.resignFirstResponder()
        updateEmptyState()
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        refreshSearchOriginIfStale()
        setSearchModeControlVisible(true)
        searchBar.setShowsCancelButton(true, animated: true)
        // Refocusing a collapsed sheet expands it again
        expandSearchSheet()
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
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
        state.clearSearch()
        userSearchWorkItem?.cancel()
        suggestedSearchWorkItem?.cancel()
        mapViewController?.setSearchFilter(nil)
        hideSearchResults()
        updateEmptyState()
    }
}

// MARK: - Custom Search Implementation
extension CirclesHomeViewController {
    // Unified place search: always searches your places AND your network's
    // (deduplicated) — the old "your places / all places" scope split was
    // low value since "all" already includes yours and the text narrows it.
    func filterPlaces(searchText: String) {
        let searchSource = deduplicatePlaces(userPlaces: userOwnPlaces, networkPlaces: networkPlaces)

        // Shared matcher (Place.matches) — the same predicate filters the map
        // pins, so this list and the pins can't drift. Apple Maps may have
        // recognised a saved "restaurant" as the deli being asked for; those
        // ids ride along to the pins too (setSearchFilter(_:matchedPlaceIds:)).
        let split = POIDuplicateMatcher.partition(candidates: appleCandidates, saved: searchSource)
        appleMatchedPlaceIds = Set(split.matched.map(\.id))
        appleVenues = split.unsaved
        filteredPlaces = searchSource.filter { appleMatchedPlaceIds.contains($0.id) || $0.matches(searchQuery: searchText) }

        // Nearest first, with the distance shown on each row ("looking for
        // pizza NEAR ME" is the whole query) — same reference the places
        // list uses: real location, else the map's center.
        // Built locally, then assigned once — `searchDistances` forwards to
        // HomeState, so per-key writes would copy the dictionary each time.
        let entries = DistancePlaceSorter.sorted(filteredPlaces, from: searchReferenceLocation())
        var distances: [String: CLLocationDistance] = [:]
        for entry in entries { if let d = entry.distance { distances[entry.place.id] = d } }
        searchDistances = distances
        filteredPlaces = entries.map(\.place)

        // Nothing saved by you or your network matches? Suggest nearby global
        // venues instead of a dead end. Centralized here so every caller
        // (keystroke, scope change, late network-places load) keeps the rule:
        // suggested exists only while the local sections are empty.
        updateSuggestedPlaces(for: searchText)

        // Network places power the search superset — load them once in the
        // background (previously only loaded when the user picked the scope).
        if networkPlaces.isEmpty && !isLoadingNetworkPlaces {
            loadNetworkPlaces()
        }
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
        let resolution = SearchOriginResolver.resolve(candidates)
        Logger.debug("🔎 search origin: \(resolution?.source.rawValue ?? "none")")
        return resolution
    }

    /// A fresh fix is worth a short wait, but the list never waits for it:
    /// results render from the best cached origin, and re-sort only if the
    /// real position turns out to be somewhere else.
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
    func rebuildSuggestedRows() {
        let saved = deduplicatePlaces(userPlaces: userOwnPlaces, networkPlaces: networkPlaces)
        let merged = SuggestedNearbyMerger.merge(global: suggestedPlaces, apple: appleVenues, saved: saved, from: searchReferenceLocation())
        suggestedRows = merged.map(\.row)
        var distances: [String: CLLocationDistance] = [:]
        for entry in merged { if let d = entry.distance { distances[entry.row.id] = d } }
        suggestedDistances = distances
    }

    /// The matched places that get a row (all of them, nearest first).
    var visibleFilteredPlaces: [Place] {
        Array(filteredPlaces.prefix(searchPlan.placeRows))
    }

    /// Debounced nearby lookup, two channels: the shared catalog (name-word
    /// prefixes) and Apple Maps (plain language — "deli" finds delis, whatever
    /// they were filed under). Runs whether or not your own places matched;
    /// HomeSearchPlan decides how many rows the answer gets.
    func updateSuggestedPlaces(for query: String) {
        suggestedSearchWorkItem?.cancel()
        // No reference point → skip: quality-ranked global hits with no
        // geo filter would confidently suggest pizza on another continent.
        guard let reference = searchReferenceLocation() else { return }
        rebuildSuggestedRows()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.fetchSuggestedPlaces(serverQuery: query, typedQuery: query,
                                      reference: reference, allowFallback: true)
            self.fetchAppleVenues(typedQuery: query, reference: reference)
        }
        suggestedSearchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// The Apple channel. Whatever comes back is split against the saved
    /// places on every filter pass (phase 1), so a saved place Apple called a
    /// deli joins PLACES and its pin stays; the rest go under MORE NEARBY.
    private func fetchAppleVenues(typedQuery: String, reference: CLLocation) {
        venueSearch.searchVenues(query: typedQuery, near: reference) { [weak self] result in
            guard let self, self.isSearching,
                  self.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) == typedQuery else { return }
            guard case .success(let venues) = result else { return }   // throttled/offline: silently nothing
            self.appleCandidates = venues
            self.filterPlaces(searchText: typedQuery)
            self.mapViewController?.setSearchFilter(self.searchMode.filtersMap(typedQuery),
                                                    matchedPlaceIds: self.searchMode == .places ? self.appleMatchedPlaceIds : [])
            self.rebuildSuggestedRows()
            self.refreshSearchOverlay()
            self.updateEmptyState()
        }
    }

    /// One SUGGESTED fetch. The server matches exact name-word PREFIXES, so a
    /// typo ("piza") returns nothing even though the local sections now
    /// forgive it — when the full query comes back empty, retry ONCE with a
    /// 3-char prefix of the longest word ("piz" does match pizza-named
    /// venues). Staleness is always checked against what the user TYPED.
    private func fetchSuggestedPlaces(serverQuery: String, typedQuery: String,
                                      reference: CLLocation, allowFallback: Bool) {
        // limit is applied server-side BEFORE the radius filter (quality
        // cut first), so ask generously and trim client-side.
        GlobalPlaceService.shared.searchGlobalPlaces(
            query: serverQuery,
            location: (lat: reference.coordinate.latitude, lng: reference.coordinate.longitude),
            radius: 80,
            limit: 50
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.isSearching,
                      self.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) == typedQuery else { return }
                guard case .success(let places) = result else { return }

                if places.isEmpty, allowFallback,
                   let longest = typedQuery.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                       .max(by: { $0.count < $1.count }),
                   longest.count >= 4 {
                    self.fetchSuggestedPlaces(serverQuery: String(longest.prefix(3)),
                                              typedQuery: typedQuery,
                                              reference: reference, allowFallback: false)
                    return
                }

                // Server sorts nearest-first when given a location; the
                // merger re-sorts once Apple's rows are in the mix.
                self.suggestedPlaces = Array(places.prefix(8))
                self.rebuildSuggestedRows()
                self.refreshSearchOverlay()
                self.updateEmptyState()
            }
        }
    }

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
        // Clear the search UI first
        searchBar.text = ""
        searchBar.resignFirstResponder()
        state.clearSearch()
        userSearchWorkItem?.cancel()
        suggestedSearchWorkItem?.cancel()
        mapViewController?.setSearchFilter(nil)
        hideSearchResults()
        updateEmptyState()

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
}

// MARK: - PlaceSearchable Navigation
extension CirclesHomeViewController {
    func navigateToPlace(_ place: Place) {
        // Find the circle this place belongs to
        var targetCircle: Circle?
        
        // Check user's circles first
        if let circleId = place.circleId, let circle = circles.first(where: { $0.id == circleId }) {
            targetCircle = circle
        }
        
        // Check network circles if not found
        if targetCircle == nil {
            if let circleId = place.circleId {
                targetCircle = networkCircles.first(where: { $0.id == circleId })
            }
        }
        
        guard let circle = targetCircle else {
            Logger.debug("⚠️ Could not find circle for place: \(place.name)")
            return
        }
        
        let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
}
