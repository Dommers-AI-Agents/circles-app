import UIKit
import MapKit
import CoreLocation

// SearchSection model and the dropdown/table delegate & data source for
// CirclesHomeViewController. Extracted from the main controller (Wave 4).

// MARK: - Search overlay sections
// The search dropdown renders SUGGESTED (nearby global venues, only when no
// local place matches) and PEOPLE. The places case remains for enum coverage
// but renders 0 rows — place matches show on the map + its list instead.
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
            switch SearchSection(rawValue: section) {
            // Place matches render on the map + its list now, never as
            // dropdown rows — the dropdown is people/suggested only
            case .places: return 0
            case .suggested: return visibleSuggestedPlaces.count
            case .people: return searchedUsers.count
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

            // SUGGESTED section: a nearby global venue nobody in your
            // network has saved — tap to view, 'i' to peek
            if SearchSection(rawValue: indexPath.section) == .suggested {
                let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
                cell.accessoryView = nil
                cell.accessoryType = .detailDisclosureButton
                guard indexPath.row < visibleSuggestedPlaces.count else { return cell }
                let suggestion = visibleSuggestedPlaces[indexPath.row]

                var content = cell.defaultContentConfiguration()
                content.text = suggestion.name
                var subtitle = suggestion.address
                if let rating = suggestion.googleData?.rating {
                    subtitle = String(format: "★ %.1f · %@", rating, subtitle)
                }
                if let distance = suggestedDistances[suggestion.id] {
                    subtitle = "\(listDistanceFormatter.string(fromDistance: distance)) · \(subtitle)"
                }
                content.secondaryText = subtitle
                content.secondaryTextProperties.color = Constants.Colors.secondaryLabel
                content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 13)
                content.image = UIImage(systemName: "sparkles")
                content.imageProperties.tintColor = .systemOrange
                cell.contentConfiguration = content
                return cell
            }

            // PLACES section: a place result
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
            cell.accessoryView = nil

            // Add bounds check
            guard indexPath.row < filteredPlaces.count else {
                return cell
            }

            let place = filteredPlaces[indexPath.row]

            var content = cell.defaultContentConfiguration()
            content.text = place.name
            
            // Show creator name and circle info
            var subtitle = ""
            
            // Check if it's the current user first
            let currentUserId = AuthService.shared.getUserId() ?? ""
            if place.addedBy == currentUserId {
                subtitle = "Added by you"
            } else {
                // Try to find the connection name from network circles
                var connectionName: String? = place.addedByUser?.displayName

                // Look through network circles to find the owner
                for networkCircle in networkCircles where connectionName == nil {
                    if let circleId = place.circleId, networkCircle.id == circleId {
                        // Found the circle, get the owner's name
                        if let ownerDetails = networkCircle.ownerDetails {
                            connectionName = ownerDetails.displayName
                        } else {
                            // Try to find from connections list
                            if let connection = NetworkManager.shared.connections.first(where: { $0.connectedUserId == networkCircle.owner }) {
                                connectionName = connection.connectedUser?.displayName
                            }
                        }
                        break
                    }
                }
                
                if let name = connectionName {
                    subtitle = "Added by \(name)"
                } else {
                    subtitle = "Added by a connection"
                }
            }
            
            // Add circle name
            if let circle = circles.first(where: { $0.id == place.circleId }) {
                subtitle += " • \(circle.name)"
            } else if let networkCircle = networkCircles.first(where: { $0.id == place.circleId }) {
                subtitle += " • \(networkCircle.name)"
            }

            // Distance leads the line — the list is sorted nearest-first
            if let distance = searchDistances[place.id] {
                subtitle = "\(listDistanceFormatter.string(fromDistance: distance)) · \(subtitle)"
            }

            content.secondaryText = subtitle
            content.secondaryTextProperties.color = Constants.Colors.secondaryLabel
            content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 13)
            
            // Add category icon
            let iconName: String
            switch place.category {
            case .restaurant, .cafe, .bar: iconName = "fork.knife"
            case .hotel: iconName = "bed.double"
            case .retail: iconName = "bag"
            case .service: iconName = "wrench.and.screwdriver"
            case .attraction: iconName = "star"
            case .entertainment: iconName = "tv"
            case .healthcare: iconName = "heart"
            case .fitness: iconName = "figure.walk"
            case .education: iconName = "graduationcap"
            case .outdoor: iconName = "tree"
            case .transport: iconName = "car"
            case .finance: iconName = "dollarsign.circle"
            case .home: iconName = "house"
            case .work: iconName = "building.2"
            case .other: iconName = "circle.grid.3x3"
            }
            content.image = UIImage(systemName: iconName)
            content.imageProperties.tintColor = Constants.Colors.primary
            
            cell.contentConfiguration = content
            // The 'i' opens a preview sheet without leaving the results
            cell.accessoryType = .detailDisclosureButton

            return cell
        }

        return UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if tableView == placesListTableView {
            return 72 // QuickAccessPlaceCell's designed row height
        }
        // Use automatic dimensions for all table views to avoid constraint conflicts
        return UITableView.automaticDimension
    }

    // Search overlay section headers (PLACES / PEOPLE) — hidden when the
    // section is empty so a places-only or people-only search reads cleanly.
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard tableView == searchResultsTableView, isSearching else { return nil }
        switch SearchSection(rawValue: section) {
        case .places: return nil // place rows moved to the map + its list
        case .suggested: return visibleSuggestedPlaces.isEmpty ? nil : "SUGGESTED NEARBY"
        case .people: return searchedUsers.isEmpty ? nil : "PEOPLE"
        case .none: return nil
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard tableView == searchResultsTableView, isSearching else { return 0 }
        switch SearchSection(rawValue: section) {
        case .places: return 0 // place rows moved to the map + its list
        case .suggested: return visibleSuggestedPlaces.isEmpty ? 0 : 28
        case .people: return searchedUsers.isEmpty ? 0 : 28
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
            guard indexPath.row < visibleSuggestedPlaces.count else { return }
            presentSearchPreview(place: visibleSuggestedPlaces[indexPath.row].toLegacyPlace(), circle: nil)
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
            case .people:
                guard indexPath.row < searchedUsers.count else { return }
                selectSearchedUser(searchedUsers[indexPath.row])
            case .suggested:
                guard indexPath.row < visibleSuggestedPlaces.count else { return }
                let suggestion = visibleSuggestedPlaces[indexPath.row]
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
                let detailVC = PlaceDetailViewController(place: suggestion.toLegacyPlace())
                navigationController?.pushViewController(detailVC, animated: true)
            default:
                // Place rows no longer render in the dropdown (they live on
                // the map + its list); unreachable, kept for enum coverage
                guard indexPath.row < filteredPlaces.count else { return }
                mapViewController?.setSearchFilter(nil)
                handleSearchResultSelection(at: indexPath)
            }
        }
    }
}
