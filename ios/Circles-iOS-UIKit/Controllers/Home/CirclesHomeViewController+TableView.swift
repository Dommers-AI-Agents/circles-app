import UIKit
import FavWidgetsCore
import MapKit
import CoreLocation

// SearchSection model and the dropdown/table delegate & data source for
// CirclesHomeViewController. Extracted from the main controller (Wave 4).

// MARK: - Search sheet sections
// One sheet for everything (Wes, 2026-10-29): PLACES (every matched saved
// place, nearest first), PEOPLE, then NEARBY (catalog + Apple venues), each
// header with its count. HomeSearchPlan says how many rows each gets.
enum SearchSection: Int, CaseIterable {
    case widgets
    case places
    case people
    case suggested
    /// One line: searching / offline / failed (tap to retry)
    case status
    /// Focused, empty bar: the person's recent searches…
    case recent
    /// …and one-tap category searches
    case browse
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
        } else if tableView == searchResultsTableView {
            let plan = searchPlan
            switch SearchSection(rawValue: section) {
            case .widgets: return plan.widgetRows
            case .places: return plan.placeRows
            case .suggested: return plan.suggestedSectionRows
            case .people: return plan.peopleSectionRows
            case .status: return plan.statusRows
            case .recent: return plan.recentRows
            case .browse: return plan.browseRows
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
        } else if tableView == searchResultsTableView {
            let query = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch SearchSection(rawValue: indexPath.section) {
            case .status:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
                let status = searchPlan.status ?? .searching
                var content = cell.defaultContentConfiguration()
                content.text = status.text
                content.textProperties.font = UIFont.systemFont(ofSize: 14)
                content.textProperties.color = Constants.Colors.secondaryLabel
                switch status {
                case .searching:
                    let spinner = UIActivityIndicatorView(style: .medium)
                    spinner.startAnimating()
                    cell.accessoryView = spinner
                    content.image = UIImage(systemName: "magnifyingglass")
                case .offline:
                    cell.accessoryView = nil
                    content.image = UIImage(systemName: "wifi.slash")
                case .failed:
                    cell.accessoryView = nil
                    content.image = UIImage(systemName: "arrow.clockwise")
                }
                content.imageProperties.tintColor = Constants.Colors.secondaryLabel
                cell.accessoryType = .none
                cell.contentConfiguration = content
                return cell
            case .recent:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
                cell.accessoryView = nil
                cell.accessoryType = .none
                let recents = visibleRecentSearches
                guard indexPath.row < recents.count else { return cell }
                var content = cell.defaultContentConfiguration()
                content.text = recents[indexPath.row]
                content.image = UIImage(systemName: "clock.arrow.circlepath")
                content.imageProperties.tintColor = Constants.Colors.secondaryLabel
                cell.contentConfiguration = content
                return cell
            case .browse:
                let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
                cell.accessoryView = nil
                cell.accessoryType = .disclosureIndicator
                let items = HomeSearchBrowseItem.all
                guard indexPath.row < items.count else { return cell }
                var content = cell.defaultContentConfiguration()
                content.text = items[indexPath.row].title
                content.secondaryText = "Near you"
                content.secondaryTextProperties.color = Constants.Colors.secondaryLabel
                content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 13)
                content.image = UIImage(systemName: items[indexPath.row].symbolName)
                content.imageProperties.tintColor = Constants.Colors.primary
                cell.contentConfiguration = content
                return cell
            default:
                break
            }

            // "Show all N": the last row of a section All cut short
            if let more = showAllRow(at: indexPath) {
                let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
                cell.accessoryView = nil
                cell.accessoryType = .disclosureIndicator
                var content = cell.defaultContentConfiguration()
                content.text = more.title
                content.textProperties.color = Constants.Colors.primary
                content.textProperties.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
                content.image = UIImage(systemName: "list.bullet")
                content.imageProperties.tintColor = Constants.Colors.primary
                cell.contentConfiguration = content
                return cell
            }

            // WIDGETS section: tap to open that widget
            if SearchSection(rawValue: indexPath.section) == .widgets {
                let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
                cell.accessoryView = nil
                cell.accessoryType = .disclosureIndicator
                let widgets = matchedWidgets
                guard indexPath.row < widgets.count else { return cell }
                let widget = widgets[indexPath.row]
                var content = cell.defaultContentConfiguration()
                content.text = widget.title
                content.secondaryText = "Widget · \(widget.subtitle)"
                content.secondaryTextProperties.color = Constants.Colors.secondaryLabel
                content.secondaryTextProperties.font = UIFont.systemFont(ofSize: 13)
                content.secondaryTextProperties.numberOfLines = 1
                content.image = UIImage(systemName: widget.symbolName)
                content.imageProperties.tintColor = UIColor(hex: widget.accentHex)
                cell.contentConfiguration = content
                return cell
            }

            // PEOPLE section: a person result
            if SearchSection(rawValue: indexPath.section) == .people {
                let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
                cell.accessoryView = nil
                cell.accessoryType = .none
                guard indexPath.row < searchedUsers.count else { return cell }
                let user = searchedUsers[indexPath.row]

                var content = cell.defaultContentConfiguration()
                content.attributedText = highlighted(user.displayName, query: query)

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
                // Tap opens the place; 'i' peeks at it without leaving the search
                cell.accessoryType = .detailDisclosureButton
                let places = visibleFilteredPlaces
                guard indexPath.row < places.count else { return cell }
                let place = places[indexPath.row]

                var content = cell.defaultContentConfiguration()
                content.attributedText = highlighted(place.name, query: query)
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
                content.attributedText = highlighted(suggestion.name, query: query)
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
        guard tableView == searchResultsTableView else { return nil }
        return searchSectionTitle(section)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard tableView == searchResultsTableView else { return 0 }
        // Same rule as the titles: a header exactly where a title is
        return searchSectionTitle(section) == nil ? 0 : SearchSheetLayout.headerHeight
    }

    /// The header over a results section, nil when it has no rows (or no header).
    func searchSectionTitle(_ section: Int) -> String? {
        let plan = searchPlan
        switch SearchSection(rawValue: section) {
        case .widgets: return plan.widgetRows == 0 ? nil : plan.widgetsHeader
        case .places: return plan.placeRows == 0 ? nil : plan.placesHeader
        case .suggested: return plan.suggestedRows == 0 ? nil : plan.suggestedHeader
        case .people: return plan.peopleRows == 0 ? nil : plan.peopleHeader
        case .recent: return plan.recentRows == 0 ? nil : "RECENT"
        case .browse: return plan.browseRows == 0 ? nil : "BROWSE NEARBY"
        case .status, .none: return nil
        }
    }
    
    // The 'i' accessory on a search result: preview the place in a sheet
    // without clearing the search — dismiss and the list is still there.
    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard tableView == searchResultsTableView else { return }
        switch SearchSection(rawValue: indexPath.section) {
        case .places:
            let places = visibleFilteredPlaces
            guard indexPath.row < places.count else { return }
            let place = places[indexPath.row]
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

        if tableView == searchResultsTableView {
            if let more = showAllRow(at: indexPath) {
                selectSearchScope(more.scope)
                return
            }
            switch SearchSection(rawValue: indexPath.section) {
            case .widgets:
                let widgets = matchedWidgets
                guard indexPath.row < widgets.count else { return }
                let id = widgets[indexPath.row].id
                AnalyticsService.shared.logEvent("home_search_widget_opened", parameters: ["widget": id])
                recordRecentSearch()
                resetSearch()
                showWidgetsTab(openingWidget: id)
            case .places:
                let places = visibleFilteredPlaces
                guard indexPath.row < places.count else { return }
                // The search (query, pins, sheet) survives the push and the pop
                recordRecentSearch()
                searchBar.resignFirstResponder()
                presentDetailForPlace(places[indexPath.row])
            case .people:
                guard indexPath.row < searchedUsers.count else { return }
                selectSearchedUser(searchedUsers[indexPath.row])
            case .suggested:
                guard indexPath.row < visibleSuggestedRows.count else { return }
                let row = visibleSuggestedRows[indexPath.row]
                recordRecentSearch()
                searchBar.text = ""
                searchBar.resignFirstResponder()
                endSearch(keepFocus: false)
                switch row {
                case .global(let suggestion):
                    let detailVC = PlaceDetailViewController(place: suggestion.toLegacyPlace())
                    navigationController?.pushViewController(detailVC, animated: true)
                case .apple(let venue):
                    // Nobody has saved it, so there is no place page to open —
                    // the useful next step is saving it, prefilled.
                    openAddPlace(prefilledWith: venue)
                }
            case .status:
                if searchPlan.status == .failed || searchPlan.status == .offline { retryFailedSearch() }
            case .recent:
                let recents = visibleRecentSearches
                guard indexPath.row < recents.count else { return }
                runSearch(recents[indexPath.row])
            case .browse:
                let items = HomeSearchBrowseItem.all
                guard indexPath.row < items.count else { return }
                AnalyticsService.shared.logEvent("home_search_browse", parameters: ["category": items[indexPath.row].query])
                runSearch(items[indexPath.row].query)
            case .none:
                break
            }
        }
    }

    /// The "Show all N people / nearby" row, when `indexPath` is one.
    func showAllRow(at indexPath: IndexPath) -> (scope: HomeSearchScope, title: String)? {
        let plan = searchPlan
        switch SearchSection(rawValue: indexPath.section) {
        case .people where plan.morePeople && indexPath.row == plan.peopleRows:
            return (.people, "Show all \(plan.peopleTotal) people")
        case .suggested where plan.moreNearby && indexPath.row == plan.suggestedRows:
            return (.nearby, "Show all \(plan.suggestedTotal) nearby")
        default:
            return nil
        }
    }

    /// Swipe a recent search away.
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard tableView == searchResultsTableView, SearchSection(rawValue: indexPath.section) == .recent else { return nil }
        let recents = visibleRecentSearches
        guard indexPath.row < recents.count else { return nil }
        let query = recents[indexPath.row]
        let remove = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, done in
            self?.recentSearches.remove(query)
            self?.refreshSearchOverlay()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }
}

// MARK: - Saving an Apple Maps venue from the search overlay
extension CirclesHomeViewController {
    /// Add Place with the venue's name and pin already in the form, into the
    /// circle used last (same rule as a shared link, SceneDelegate).
    func openAddPlace(prefilledWith venue: Place) {
        // The home screen already holds the circles (profile order); only ask
        // the server when it has none yet (still loading, or a failed load)
        if !circles.isEmpty {
            pushAddPlace(prefilledWith: venue, circles: circles)
            return
        }
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .success(let circles) = result, !circles.isEmpty else {
                    self?.showError("Create a circle first, then save places into it.")
                    return
                }
                self.pushAddPlace(prefilledWith: venue, circles: circles)
            }
        }
    }

    private func pushAddPlace(prefilledWith venue: Place, circles: [Circle]) {
        let lastUsedId = UserDefaults.standard.string(forKey: AddPlaceViewController.lastUsedCircleKey)
        let target = circles.first(where: { $0.id == lastUsedId }) ?? circles[0]
        let addPlaceVC = AddPlaceViewController(circleId: target.id, circles: circles)
        addPlaceVC.circleWasRemembered = target.id == lastUsedId && circles.count > 1
        addPlaceVC.prefillSearchWithPlace(name: venue.name, coordinate: venue.location?.clLocation?.coordinate)
        navigationController?.pushViewController(addPlaceVC, animated: true)
    }
}
