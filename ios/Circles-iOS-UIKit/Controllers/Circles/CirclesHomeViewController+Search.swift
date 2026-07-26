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

        guard !trimmed.isEmpty else {
            isSearching = false
            filteredPlaces = []
            searchedUsers = []
            userSearchWorkItem?.cancel()
            hideSearchResults()
            updateEmptyState()
            return
        }

        isSearching = true

        // Places — local, instant
        filterPlaces(searchText: trimmed)

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
    func refreshSearchOverlay() {
        if isSearching && (!filteredPlaces.isEmpty || !searchedUsers.isEmpty) {
            showSearchResults()
        } else {
            hideSearchResults()
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // Dismiss the keyboard when "Done" is tapped
        searchBar.resignFirstResponder()
        // Update empty state if needed
        updateEmptyState()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        isSearching = false
        filteredPlaces = []
        searchedUsers = []
        userSearchWorkItem?.cancel()
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

        filteredPlaces = searchSource.filter { place in
            place.name.localizedCaseInsensitiveContains(searchText) ||
            place.address.localizedCaseInsensitiveContains(searchText) ||
            (place.description ?? "").localizedCaseInsensitiveContains(searchText) ||
            (place.notes ?? "").localizedCaseInsensitiveContains(searchText) ||
            (place.publicNotes ?? "").localizedCaseInsensitiveContains(searchText) ||
            (place.privateNotes ?? "").localizedCaseInsensitiveContains(searchText)
        }

        // Network places power the search superset — load them once in the
        // background (previously only loaded when the user picked the scope).
        if networkPlaces.isEmpty && !isLoadingNetworkPlaces {
            loadNetworkPlaces()
        }
    }

    /// Sizes the unified overlay for both the PLACES and PEOPLE sections
    /// (each with a header), capped so it never swallows the whole screen.
    func showSearchResults() {
        let cellHeight: CGFloat = 60
        let headerHeight: CGFloat = 28
        let placeRows = min(filteredPlaces.count, 6)
        let userRows = min(searchedUsers.count, 6)

        var height: CGFloat = 0
        if placeRows > 0 { height += headerHeight + CGFloat(placeRows) * cellHeight }
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
        userSearchWorkItem?.cancel()
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
