import UIKit
import MapKit
import CoreLocation

// Search-bar delegate, custom place/people search, and PlaceSearchable
// navigation for CirclesHomeViewController. Extracted (Wave 4).

// MARK: - UISearchBarDelegate
extension CirclesHomeViewController: UISearchBarDelegate {
    // Unified search: places filter instantly (local), people are fetched from
    // the server (debounced). Results render in one overlay as PLACES / PEOPLE.
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Editing the query brings the results list back after a map peek
        isSearchOverlayDismissed = false

        guard !trimmed.isEmpty else {
            isSearching = false
            filteredPlaces = []
            searchedUsers = []
            searchDistances = [:]
            suggestedPlaces = []
            suggestedDistances = [:]
            userSearchWorkItem?.cancel()
            suggestedSearchWorkItem?.cancel()
            mapViewController?.setSearchFilter(nil)
            hideSearchResults()
            updateEmptyState()
            return
        }

        isSearching = true

        // Places — local, instant
        filterPlaces(searchText: trimmed)

        // The pins narrow with the text too (FSM debounces internally; no
        // zoom — the results overlay covers the embedded map while typing)
        mapViewController?.setSearchFilter(trimmed)

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

    /// Shows the results overlay if either section has matches, hides it otherwise.
    /// A map peek (Done) keeps it down until the user edits or refocuses the bar
    /// — late async results (people fetch, suggested venues) must not yank the
    /// map away again.
    func refreshSearchOverlay() {
        if isSearching && !isSearchOverlayDismissed
            && (!filteredPlaces.isEmpty || !searchedUsers.isEmpty || !visibleSuggestedPlaces.isEmpty) {
            showSearchResults()
        } else {
            hideSearchResults()
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        // "Search" while results are up = show me the MAP (same peek a tap on
        // the visible map enters)
        enterSearchMapPeek()
        updateEmptyState()
    }

    /// MAP PEEK: hide the results list while the search — and the filtered
    /// pins — stay live. Entered by tapping the visible map or the keyboard's
    /// Search key; exited via the Show List pill or refocusing/editing the bar.
    func enterSearchMapPeek() {
        guard isSearching, !isSearchOverlayDismissed else { return }
        isSearchOverlayDismissed = true
        searchBar.resignFirstResponder()
        hideSearchResults()
    }

    @objc func showListFromMapPeek() {
        isSearchOverlayDismissed = false
        refreshSearchOverlay()
        updateSearchListToggle()
    }

    /// The Show List pill exists exactly while a peek is active.
    func updateSearchListToggle() {
        searchListToggleButton.isHidden = !(isSearching && isSearchOverlayDismissed)
    }

    /// Overrides the PlaceSearchable default (same animation) so EVERY hide
    /// path — clears, result taps, peeks — keeps the Show List pill in sync.
    func hideSearchResults() {
        UIView.animate(withDuration: 0.3) {
            self.searchResultsTableView.alpha = 0
            self.searchResultsHeightConstraint?.constant = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.searchResultsTableView.isHidden = true
        }
        updateSearchListToggle()
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
        // Refocusing after a map peek restores the results list
        if isSearching && isSearchOverlayDismissed {
            isSearchOverlayDismissed = false
            refreshSearchOverlay()
        }
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        isSearching = false
        isSearchOverlayDismissed = false
        filteredPlaces = []
        searchedUsers = []
        searchDistances = [:]
        suggestedPlaces = []
        suggestedDistances = [:]
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
        // pins, so this list and the pins can't drift.
        filteredPlaces = searchSource.filter { $0.matches(searchQuery: searchText) }

        // Nearest first, with the distance shown on each row ("looking for
        // pizza NEAR ME" is the whole query) — same reference the places
        // list uses: real location, else the map's center.
        searchDistances = [:]
        if let reference = searchReferenceLocation() {
            for place in filteredPlaces {
                if let location = place.location?.clLocation {
                    searchDistances[place.id] = reference.distance(from: location)
                }
            }
        }
        filteredPlaces.sort { lhs, rhs in
            switch (searchDistances[lhs.id], searchDistances[rhs.id]) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }

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

    /// The point "near" means: the user's real location when we have it,
    /// otherwise the center of the map they're looking at.
    func searchReferenceLocation() -> CLLocation? {
        mapViewController?.currentUserLocation
            ?? mapViewController.map { CLLocation(latitude: $0.currentRegion.center.latitude, longitude: $0.currentRegion.center.longitude) }
    }

    /// SUGGESTED rows render only while there are no local place results.
    var visibleSuggestedPlaces: [GlobalPlace] {
        filteredPlaces.isEmpty ? suggestedPlaces : []
    }

    /// Debounced global-venue lookup for the SUGGESTED fallback section.
    func updateSuggestedPlaces(for query: String) {
        suggestedSearchWorkItem?.cancel()
        guard filteredPlaces.isEmpty else {
            suggestedPlaces = []
            suggestedDistances = [:]
            return
        }
        // No reference point → skip: quality-ranked global hits with no
        // geo filter would confidently suggest pizza on another continent.
        guard let reference = searchReferenceLocation() else { return }

        let work = DispatchWorkItem { [weak self] in
            // limit is applied server-side BEFORE the radius filter (quality
            // cut first), so ask generously and trim client-side.
            GlobalPlaceService.shared.searchGlobalPlaces(
                query: query,
                location: (lat: reference.coordinate.latitude, lng: reference.coordinate.longitude),
                radius: 80,
                limit: 50
            ) { result in
                DispatchQueue.main.async {
                    guard let self = self, self.isSearching,
                          self.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) == query,
                          self.filteredPlaces.isEmpty else { return }
                    if case .success(let places) = result {
                        // Server sorts nearest-first when given a location
                        self.suggestedPlaces = Array(places.prefix(8))
                        self.suggestedDistances = [:]
                        for place in self.suggestedPlaces {
                            if let location = place.location?.clLocation {
                                self.suggestedDistances[place.id] = reference.distance(from: location)
                            }
                        }
                        self.refreshSearchOverlay()
                        self.updateEmptyState()
                    }
                }
            }
        }
        suggestedSearchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
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

    /// Sizes the unified overlay for both the PLACES and PEOPLE sections
    /// (each with a header), capped so it never swallows the whole screen.
    func showSearchResults() {
        let cellHeight: CGFloat = 60
        let headerHeight: CGFloat = 28
        let placeRows = min(filteredPlaces.count, 6)
        let suggestedRows = min(visibleSuggestedPlaces.count, 6)
        let userRows = min(searchedUsers.count, 6)

        var height: CGFloat = 0
        if placeRows > 0 { height += headerHeight + CGFloat(placeRows) * cellHeight }
        if suggestedRows > 0 { height += headerHeight + CGFloat(suggestedRows) * cellHeight }
        if userRows > 0 { height += headerHeight + CGFloat(userRows) * cellHeight }
        height = min(height, 400) // cap — the overlay scrolls beyond this

        searchResultsTableView.isHidden = false
        searchResultsTableView.isScrollEnabled = true
        searchResultsHeightConstraint?.constant = height

        UIView.animate(withDuration: 0.3) {
            self.searchResultsTableView.alpha = 1
            self.view.layoutIfNeeded()
        }
        searchResultsTableView.reloadData()
        updateSearchListToggle()
    }

    /// Handles a tap on a PEOPLE result: connections/followees filter the map
    /// (like tapping their avatar); everyone else opens their profile to act.
    func selectSearchedUser(_ user: User) {
        // Clear the search UI first
        searchBar.text = ""
        searchBar.resignFirstResponder()
        isSearching = false
        filteredPlaces = []
        searchedUsers = []
        searchDistances = [:]
        suggestedPlaces = []
        suggestedDistances = [:]
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
    
    // Load network places for search
    func loadNetworkPlaces() {
        guard !isLoadingNetworkPlaces else { return }
        
        isLoadingNetworkPlaces = true
        Logger.debug("🔍 Loading network places for search...")
        
        let group = DispatchGroup()
        var allNetworkPlaces: [Place] = []
        
        // If we don't have network circles, fetch them first
        if networkCircles.isEmpty {
            group.enter()
            APIService.shared.request(
                endpoint: "network/my-network-circles",
                method: .get,
                requiresAuth: true
            ) { [weak self] (result: Result<CirclesDataResponse, APIError>) in
                switch result {
                case .success(let response):
                    self?.networkCircles = response.data
                    // Now fetch places from network circles
                    for circle in response.data {
                        group.enter()
                        PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                            switch result {
                            case .success(let places):
                                allNetworkPlaces.append(contentsOf: places)
                            case .failure(let error):
                                Logger.debug("Failed to fetch places for network circle \(circle.id): \(error)")
                            }
                            group.leave()
                        }
                    }
                case .failure(let error):
                    Logger.debug("Failed to fetch network circles: \(error)")
                }
                group.leave()
            }
        } else {
            // Use existing network circles
            for circle in networkCircles {
                group.enter()
                PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { result in
                    switch result {
                    case .success(let places):
                        allNetworkPlaces.append(contentsOf: places)
                    case .failure(let error):
                        Logger.debug("Failed to fetch places for network circle \(circle.id): \(error)")
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoadingNetworkPlaces = false
            
            // Deduplicate network places before storing
            let deduplicatedNetworkPlaces = self.removeDuplicatePlaces(allNetworkPlaces)
            self.networkPlaces = deduplicatedNetworkPlaces
            Logger.debug("🔍 Loaded \(allNetworkPlaces.count) raw network places, deduplicated to \(deduplicatedNetworkPlaces.count) unique places for search")
            
            // If a search is active, fold the newly-loaded network places into
            // the current results
            if self.isSearching, let text = self.searchBar.text, !text.isEmpty {
                self.filterPlaces(searchText: text)
                self.refreshSearchOverlay()
                self.updateEmptyState()
            }
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
