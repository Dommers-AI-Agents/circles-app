import UIKit
import MapKit
import CoreLocation

// SearchSection model and the dropdown/table delegate & data source for
// CirclesHomeViewController. Extracted from the main controller (Wave 4).

// MARK: - Search sheet sections
// PLACES (every matched saved place, nearest first), SUGGESTED/MORE NEARBY
// (catalog + Apple venues) and PEOPLE. HomeSearchPlan says how many rows each
// gets for the current mode.
enum SearchSection: Int, CaseIterable {
    case places
    case suggested
    case people
}

// MARK: - Dropdown TableView Delegate & DataSource
extension CirclesHomeViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        // Only the search overlay is sectioned (Places / People); every other
        // shared table stays single-section.
        return tableView == searchResultsTableView ? SearchSection.allCases.count : 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == placesListTableView {
            return distanceSortedPlaces.count
        } else if tableView == searchScopeTableView {
            return SearchScope.allCases.count
        } else if tableView == searchResultsTableView {
            guard isSearching else { return 0 }
            let plan = searchPlan
            switch SearchSection(rawValue: section) {
            case .places: return plan.placeRows
            case .suggested: return plan.suggestedRows
            case .people: return plan.peopleRows
            case .none: return 0
            }
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == placesListTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "HomePlaceListCell", for: indexPath) as! QuickAccessPlaceCell
            guard indexPath.row < distanceSortedPlaces.count else { return cell }
            let entry = distanceSortedPlaces[indexPath.row]
            let distanceText = entry.distance.map { listDistanceFormatter.string(fromDistance: $0) }
            cell.configure(with: entry.place, isSelected: false, distanceText: distanceText,
                           savedBy: savedByText(entry.savedBy))
            return cell
        } else if tableView == searchScopeTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchScopeCell") ?? UITableViewCell(style: .default, reuseIdentifier: "SearchScopeCell")
            
            cell.backgroundColor = .clear
            cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            cell.selectionStyle = .default
            
            // Set selection background color
            let selectedView = UIView()
            selectedView.backgroundColor = Constants.Colors.primary.withAlphaComponent(0.1)
            cell.selectedBackgroundView = selectedView
            
            // Add bounds check
            guard indexPath.row < SearchScope.allCases.count else {
                return cell
            }
            
            let scope = SearchScope.allCases[indexPath.row]
            cell.textLabel?.text = scope.title
            cell.textLabel?.textColor = currentSearchScope == scope ? Constants.Colors.primary : Constants.Colors.label
            cell.accessoryType = currentSearchScope == scope ? .checkmark : .none
            
            return cell
        } else if tableView == searchResultsTableView {
            // PEOPLE section: a person result
            if SearchSection(rawValue: indexPath.section) == .people {
                let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
                cell.accessoryView = nil
                cell.accessoryType = .none
                guard indexPath.row < searchedUsers.count else { return cell }
                let user = searchedUsers[indexPath.row]

                var content = cell.defaultContentConfiguration()
                content.text = user.displayName

                let isConnected = user.connectionStatus == "connected" || user.connectionStatus == "accepted"
                let isFollowing = user.isFollowing == true
                if isConnected {
                    content.secondaryText = "Connected · tap to see on map"
                } else if isFollowing {
                    content.secondaryText = "Following · tap to see on map"
                } else {
                    content.secondaryText = "Tap to view profile"
                }
                content.secondaryTextProperties.color = Constants.Colors.secondaryLabel
                content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 13)
                content.image = UIImage(systemName: "person.crop.circle.fill")
                content.imageProperties.tintColor = Constants.Colors.primary
                cell.contentConfiguration = content
                cell.accessoryType = (isConnected || isFollowing) ? .none : .disclosureIndicator
                return cell
            }

            // PLACES section: somewhere already saved, by this user or by
            // their network. The row is the point — the map filtering alone
            // gave the user nothing to tap.
            if SearchSection(rawValue: indexPath.section) == .places {
                let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
                cell.accessoryView = nil
                cell.accessoryType = .disclosureIndicator
                let places = visibleFilteredPlaces
                guard indexPath.row < places.count else { return cell }
                let place = places[indexPath.row]

                var content = cell.defaultContentConfiguration()
                content.text = place.name
                var subtitle = place.address
                if let distance = searchDistances[place.id] {
                    subtitle = "\(listDistanceFormatter.string(fromDistance: distance)) · \(subtitle)"
                }
                content.secondaryText = subtitle
                content.secondaryTextProperties.color = Constants.Colors.secondaryLabel
                content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 13)
                content.secondaryTextProperties.numberOfLines = 1
                content.image = UIImage(systemName: place.category.symbolName)
                content.imageProperties.tintColor = Constants.Colors.primary
                cell.contentConfiguration = content
                return cell
            }

            // SUGGESTED section: a nearby global venue nobody in your
            // network has saved — tap to view, 'i' to peek
            if SearchSection(rawValue: indexPath.section) == .suggested {
                let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
                cell.accessoryView = nil
                cell.accessoryType = .detailDisclosureButton
                guard indexPath.row < visibleSuggestedRows.count else { return cell }
                let row = visibleSuggestedRows[indexPath.row]
                let suggestion = row.place

                var content = cell.defaultContentConfiguration()
                content.text = suggestion.name
                var subtitle = suggestion.address
                if let rating = suggestion.rating {
                    subtitle = String(format: "★ %.1f · %@", rating, subtitle)
                }
                if let distance = suggestedDistances[row.id] {
                    subtitle = "\(listDistanceFormatter.string(fromDistance: distance)) · \(subtitle)"
                }
                content.secondaryText = subtitle
                content.secondaryTextProperties.color = Constants.Colors.secondaryLabel
                content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 13)
                // Catalog venues keep their sparkle; an Apple Maps venue is a
                // pin nobody has saved yet.
                if case .apple = row {
                    content.image = UIImage(systemName: "mappin.and.ellipse")
                    content.imageProperties.tintColor = Constants.Colors.primary
                } else {
                    content.image = UIImage(systemName: "sparkles")
                    content.imageProperties.tintColor = .systemOrange
                }
                cell.contentConfiguration = content
                return cell
            }

        }

        return UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if tableView == placesListTableView {
            return 72 // QuickAccessPlaceCell's designed row height
        }
        if tableView == searchResultsTableView {
            return SearchSheetLayout.rowHeight // the sheet's height math assumes it
        }
        // Use automatic dimensions for all table views to avoid constraint conflicts
        return UITableView.automaticDimension
    }

    // Search overlay section headers (PLACES / PEOPLE) — hidden when the
    // section is empty so a places-only or people-only search reads cleanly.
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard tableView == searchResultsTableView, isSearching else { return nil }
        switch SearchSection(rawValue: section) {
        case .places: return searchPlan.placeRows == 0 ? nil : searchPlan.placesHeader
        case .suggested: return searchPlan.suggestedRows == 0 ? nil : searchPlan.suggestedHeader
        case .people: return searchPlan.peopleRows == 0 ? nil : "PEOPLE"
        case .none: return nil
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard tableView == searchResultsTableView, isSearching else { return 0 }
        switch SearchSection(rawValue: section) {
        case .places: return searchPlan.placeRows == 0 ? 0 : SearchSheetLayout.headerHeight
        case .suggested: return searchPlan.suggestedRows == 0 ? 0 : SearchSheetLayout.headerHeight
        case .people: return searchPlan.peopleRows == 0 ? 0 : SearchSheetLayout.headerHeight
        case .none: return 0
        }
    }
    
    // The 'i' accessory on a search result: preview the place in a sheet
    // without clearing the search — dismiss and the list is still there.
    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard tableView == searchResultsTableView else { return }
        switch SearchSection(rawValue: indexPath.section) {
        case .places:
            guard indexPath.row < filteredPlaces.count else { return }
            let place = filteredPlaces[indexPath.row]
            presentSearchPreview(place: place, circle: resolveCircle(for: place))
        case .suggested:
            guard indexPath.row < visibleSuggestedRows.count else { return }
            presentSearchPreview(place: visibleSuggestedRows[indexPath.row].place, circle: nil)
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if tableView == placesListTableView {
            guard indexPath.row < distanceSortedPlaces.count else { return }
            presentDetailForPlace(distanceSortedPlaces[indexPath.row].place)
            return
        }

        if tableView == searchScopeTableView {
            // Add bounds check
            guard indexPath.row < SearchScope.allCases.count else { return }
            
            let selectedScope = SearchScope.allCases[indexPath.row]
            currentSearchScope = selectedScope
            
            // Update search bar placeholder
            searchBar.placeholder = selectedScope.placeholder
            
            // If currently searching, refresh the search results with new scope
            if isSearching {
                filterPlaces(searchText: searchBar.text ?? "")
            }
            
            // Load network places if switching to network search and not already loaded
            if selectedScope == .networkPlaces && networkPlaces.isEmpty && !isLoadingNetworkPlaces {
                loadNetworkPlaces()
            }
            
            // Update UI and hide dropdown
            hideSearchScopeDropdown()
            isSearchScopeDropdownOpen = false
        } else if tableView == searchResultsTableView {
            switch SearchSection(rawValue: indexPath.section) {
            case .places:
                let places = visibleFilteredPlaces
                guard indexPath.row < places.count else { return }
                // The search (query, pins, sheet) survives the push and the pop
                searchBar.resignFirstResponder()
                presentDetailForPlace(places[indexPath.row])
            case .people:
                guard indexPath.row < searchedUsers.count else { return }
                selectSearchedUser(searchedUsers[indexPath.row])
            case .suggested:
                guard indexPath.row < visibleSuggestedRows.count else { return }
                let row = visibleSuggestedRows[indexPath.row]
                searchBar.text = ""
                searchBar.resignFirstResponder()
                state.clearSearch()
                userSearchWorkItem?.cancel()
                suggestedSearchWorkItem?.cancel()
                mapViewController?.setSearchFilter(nil)
                hideSearchResults()
                updateEmptyState()
                switch row {
                case .global(let suggestion):
                    let detailVC = PlaceDetailViewController(place: suggestion.toLegacyPlace())
                    navigationController?.pushViewController(detailVC, animated: true)
                case .apple(let venue):
                    // Nobody has saved it, so there is no place page to open —
                    // the useful next step is saving it, prefilled.
                    openAddPlace(prefilledWith: venue)
                }
            case .none:
                break
            }
        }
    }
}

// MARK: - Saving an Apple Maps venue from the search overlay
extension CirclesHomeViewController {
    /// Add Place with the venue's name and pin already in the form, into the
    /// circle used last (same rule as a shared link, SceneDelegate).
    func openAddPlace(prefilledWith venue: Place) {
        let coordinate = venue.location?.clLocation?.coordinate
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .success(let circles) = result, !circles.isEmpty else {
                    self?.showError("Create a circle first, then save places into it.")
                    return
                }
                let lastUsedId = UserDefaults.standard.string(forKey: AddPlaceViewController.lastUsedCircleKey)
                let target = circles.first(where: { $0.id == lastUsedId }) ?? circles[0]
                let addPlaceVC = AddPlaceViewController(circleId: target.id, circles: circles)
                addPlaceVC.prefillSearchWithPlace(name: venue.name, coordinate: coordinate)
                self.navigationController?.pushViewController(addPlaceVC, animated: true)
            }
        }
    }
}
