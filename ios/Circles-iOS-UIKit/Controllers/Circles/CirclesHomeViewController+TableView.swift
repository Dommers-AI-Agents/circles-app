import UIKit
import MapKit
import CoreLocation

// SearchSection model and the dropdown/table delegate & data source for
// CirclesHomeViewController. Extracted from the main controller (Wave 4).

// MARK: - Search overlay sections
// The unified search overlay has two sections: places first, then people.
enum SearchSection: Int, CaseIterable {
    case places
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
            case .places: return filteredPlaces.count
            case .people: return searchedUsers.count
            case .none: return 0
            }
        } else if tableView == activityTableView {
            return feedItems.count
        } else if tableView == specialsTableView {
            return specials.count
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == placesListTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "HomePlaceListCell", for: indexPath) as! QuickAccessPlaceCell
            guard indexPath.row < distanceSortedPlaces.count else { return cell }
            let entry = distanceSortedPlaces[indexPath.row]
            let distanceText = entry.distance.map { listDistanceFormatter.string(fromDistance: $0) }
            cell.configure(with: entry.place, isSelected: false, distanceText: distanceText)
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

            // PLACES section: a place result
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)

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
            cell.accessoryType = .disclosureIndicator
            
            return cell
        } else if tableView == activityTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: ActivityFeedCell.identifier, for: indexPath) as! ActivityFeedCell

            guard let item = activityFeedItem(at: indexPath.row) else {
                return cell
            }

            cell.delegate = self
            switch item {
            case .single(let activity):
                cell.configure(with: activity)
                cell.setGroupChildStyle(false)
            case .groupChild(let activity):
                cell.configure(with: activity)
                cell.setGroupChildStyle(true)
            case .group(let groupActivities):
                cell.configure(withGroup: groupActivities,
                               isExpanded: expandedGroupKeys.contains(groupActivities[0].id))
                cell.setGroupChildStyle(false)
            }
            return cell
        } else if tableView == specialsTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: SpecialItemCell.identifier, for: indexPath) as! SpecialItemCell
            guard indexPath.row < specials.count else { return cell }
            cell.configure(with: specials[indexPath.row])
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
        case .places: return filteredPlaces.isEmpty ? nil : "PLACES"
        case .people: return searchedUsers.isEmpty ? nil : "PEOPLE"
        case .none: return nil
        }
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard tableView == searchResultsTableView, isSearching else { return 0 }
        switch SearchSection(rawValue: section) {
        case .places: return filteredPlaces.isEmpty ? 0 : 28
        case .people: return searchedUsers.isEmpty ? 0 : 28
        case .none: return 0
        }
    }
    
    // Long-press a Specials row to share the deal (with the place link)
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard tableView == specialsTableView, indexPath.row < specials.count else { return nil }
        let item = specials[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.shareSpecial(item)
            }
            return UIMenu(children: [share])
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if tableView == placesListTableView {
            guard indexPath.row < distanceSortedPlaces.count else { return }
            presentDetailForPlace(distanceSortedPlaces[indexPath.row].place)
            return
        }

        if tableView == specialsTableView {
            guard indexPath.row < specials.count else { return }
            openSpecialPlace(specials[indexPath.row].venue)
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
            if SearchSection(rawValue: indexPath.section) == .people {
                guard indexPath.row < searchedUsers.count else { return }
                selectSearchedUser(searchedUsers[indexPath.row])
            } else {
                guard indexPath.row < filteredPlaces.count else { return }
                handleSearchResultSelection(at: indexPath)
            }
        } else if tableView == activityTableView {
            guard let item = activityFeedItem(at: indexPath.row) else { return }

            // Group summary rows expand/collapse in place
            let activity: Activity
            switch item {
            case .single(let a), .groupChild(let a):
                activity = a
            case .group(let groupActivities):
                toggleActivityGroup(withKey: groupActivities[0].id)
                return
            }

            // Navigate based on activity type
            switch activity.type {
            case .placeAdded, .placeLiked, .placeCommented, .photoUploaded, .placeDiscovered:
                // Navigate to the place
                navigateToPlace(withId: activity.targetId)
            case .commentLiked:
                // targetId is the COMMENT id for these; the place lives in metadata
                if let placeId = activity.metadata?.placeId {
                    navigateToPlace(withId: placeId)
                }
            case .circleCreated, .circleLiked, .circleCommented:
                // Navigate to the circle
                navigateToCircle(withId: activity.targetId)
            case .checkIn:
                // Navigate to the check-in place
                navigateToCheckInPlace(activity: activity)
            case .videoUploaded, .videoLiked:
                // Navigate to the video (targetId is the video ID for video activities)
                navigateToVideo(withId: activity.targetId)
            case .commentAdded:
                // Target varies (place, circle, moment) - only navigate when it's a known kind
                if activity.targetType == "circle" {
                    navigateToCircle(withId: activity.targetId)
                } else if activity.targetType == "place" {
                    navigateToPlace(withId: activity.targetId)
                }
            case .venueAnnouncement, .venueOffer:
                // targetId is the venue's canonical globalPlaces id — open the
                // place page the same way the Specials tab does
                navigateToGlobalPlace(withId: activity.targetId)
            case .globalPlaceLiked, .suggestionSent, .suggestionAccepted,
                 .profileUpdated, .userActivity, .reactionAdded, .unknown:
                // No reliable local destination for these
                break
            }
        }
    }
}
