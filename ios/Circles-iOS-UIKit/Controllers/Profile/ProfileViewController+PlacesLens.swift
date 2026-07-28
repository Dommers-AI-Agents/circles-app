import UIKit
import CoreLocation

// MARK: - Places lens
//
// A view of every place you've saved, cutting straight across circles.
//
// Circles get organised several different ways at once — by city, by type, by
// who recommended them, by the trip they came from — and each of those is a
// perfectly good answer to a different question. The problem isn't that the
// circles are wrong; it's that there was no way to ask "just show me the
// coffee places in Charlotte" without knowing which circle someone happened to
// file them under.
//
// So this doesn't reorganise anything. Circles stay exactly as they are, and
// this sits beside them as a second way to look at the same places. The
// category and city filters already existed — they were just buried inside the
// map's hamburger menu, which meant a filter you couldn't find on a view you
// had to switch to first.

extension ProfileViewController {

    // MARK: Setup

    func setupPlacesLens() {
        guard placesLensContainer.superview == nil else { return }

        contentView.addSubview(placesLensContainer)
        placesLensContainer.addSubview(placesCategoryChipBar)
        placesCityChipBar.translatesAutoresizingMaskIntoConstraints = false
        placesLensContainer.addSubview(placesCityChipBar)
        placesLensContainer.addSubview(placesLensTableView)
        placesLensContainer.addSubview(placesLensEmptyLabel)

        placesCategoryChipBar.onSelect = { [weak self] group in
            guard let self = self else { return }
            self.selectedPlacesGroup = group
            self.applyPlacesLensFilters()
        }

        placesCityChipBar.onSelect = { [weak self] groupId in
            guard let self = self else { return }
            // "__all" is the sentinel for the leading All chip.
            self.selectedRegionGroupId = (groupId == "__all") ? nil : groupId
            self.applyPlacesLensFilters()
        }

        placesLensTableView.dataSource = self
        placesLensTableView.delegate = self

        NSLayoutConstraint.activate([
            placesCategoryChipBar.topAnchor.constraint(equalTo: placesLensContainer.topAnchor, constant: 4),
            placesCategoryChipBar.leadingAnchor.constraint(equalTo: placesLensContainer.leadingAnchor),
            placesCategoryChipBar.trailingAnchor.constraint(equalTo: placesLensContainer.trailingAnchor),
            placesCategoryChipBar.heightAnchor.constraint(equalToConstant: 36),

            placesCityChipBar.topAnchor.constraint(equalTo: placesCategoryChipBar.bottomAnchor, constant: 6),
            placesCityChipBar.leadingAnchor.constraint(equalTo: placesLensContainer.leadingAnchor),
            placesCityChipBar.trailingAnchor.constraint(equalTo: placesLensContainer.trailingAnchor),
            placesCityChipBar.heightAnchor.constraint(equalToConstant: 36),

            placesLensTableView.topAnchor.constraint(equalTo: placesCityChipBar.bottomAnchor, constant: 6),
            placesLensTableView.leadingAnchor.constraint(equalTo: placesLensContainer.leadingAnchor),
            placesLensTableView.trailingAnchor.constraint(equalTo: placesLensContainer.trailingAnchor),
            placesLensTableView.bottomAnchor.constraint(equalTo: placesLensContainer.bottomAnchor),

            placesLensEmptyLabel.centerXAnchor.constraint(equalTo: placesLensContainer.centerXAnchor),
            placesLensEmptyLabel.topAnchor.constraint(equalTo: placesLensTableView.topAnchor, constant: 40),
            placesLensEmptyLabel.leadingAnchor.constraint(equalTo: placesLensContainer.leadingAnchor, constant: 32),
            placesLensEmptyLabel.trailingAnchor.constraint(equalTo: placesLensContainer.trailingAnchor, constant: -32)
        ])
    }

    // MARK: Chips

    /// Rebuilds both chip rows from whatever is actually saved, so a filter is
    /// never offered for something that would come back empty.
    ///
    /// Region chips are adaptive (see RegionGrouper): grouped by state, split
    /// into cities only when a state has too many places for one chip, tiny
    /// groups merged — so the bar reads "New Jersey (102) · Charlotte (31) ·
    /// Arizona (34)" instead of a parade of one-place ZIP codes.
    func refreshPlacesLensChips() {
        let groups = PlaceCategoryGroup.present(in: allPlaces.map { $0.category.rawValue })
        placesCategoryChipBar.setGroups(groups, selected: selectedPlacesGroup)

        placesRegionGroups = RegionGrouper.groups(for: allPlaces, origin: placesLensOrigin)
        // A stale selection (places changed underneath it) resets to All.
        if selectedRegionGroupId != nil && selectedRegionGroup == nil {
            selectedRegionGroupId = nil
        }
        var items: [BrowseChipBar.Item] = [BrowseChipBar.Item(id: "__all", title: "All places")]
        items.append(contentsOf: placesRegionGroups.map {
            BrowseChipBar.Item(id: $0.id, title: "\($0.title) (\($0.count))")
        })
        placesCityChipBar.setItems(items, selectedId: selectedRegionGroupId ?? "__all")
    }

    /// Where to measure from — nil until a fix has been resolved, which is a
    /// normal state, not an error. Everything degrades to volume ordering.
    var placesLensOrigin: CLLocation? { placesLensResolvedLocation }

    /// Resolves a location once, then re-sorts. Safe to call repeatedly.
    func refreshPlacesLensLocation() {
        guard placesLensResolvedLocation == nil else { return }
        placesLensLocationProvider.requestLocation { [weak self] location in
            DispatchQueue.main.async {
                guard let self = self, let location = location else { return }
                self.placesLensResolvedLocation = location
                // The fix changes city ranking, so both chips and rows restack.
                self.refreshPlacesLensChips()
                self.reloadPlacesLens()
            }
        }
    }

    // MARK: Filtering

    /// Shared filters (city, connections) go through the existing
    /// `filterPlaces()` so there's only one copy of those rules. The category
    /// group is applied here instead of via `selectedCategory`, because a group
    /// can span several raw categories — `.other` covers other/home/work — and
    /// squeezing it into a single `PlaceCategory` would quietly drop places.
    func applyPlacesLensFilters() {
        filterPlaces()
        reloadPlacesLens()
    }

    func reloadPlacesLens() {
        // filterPlaces() already applied the region + category-group filters
        // (so the Map tab sees the same set); this just orders the rows.
        let matchingGroup = filteredPlaces

        // Rows follow the same region ranking as the chips, so the two never
        // disagree about what comes first. Within a region, city then name —
        // stable blocks someone can actually scan.
        var groupRank: [String: Int] = [:]
        for (index, group) in placesRegionGroups.enumerated() {
            for placeId in group.placeIds { groupRank[placeId] = index }
        }

        placesLensRows = matchingGroup.sorted { lhs, rhs in
            let lhsRank = groupRank[lhs.id] ?? Int.max
            let rhsRank = groupRank[rhs.id] ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            let lhsCity = lhs.lensCity ?? ""
            let rhsCity = rhs.lensCity ?? ""
            if lhsCity != rhsCity { return lhsCity < rhsCity }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        placesLensTableView.reloadData()

        let isEmpty = placesLensRows.isEmpty
        placesLensEmptyLabel.isHidden = !isEmpty
        if isEmpty {
            placesLensEmptyLabel.text = allPlaces.isEmpty
                ? "Places you save will show up here, across all your circles."
                : "Nothing saved matching these filters yet."
        }

        updatePlacesLensHeight()
    }

    /// The lens lives in a scroll view, so the table has to be as tall as its
    /// content rather than scrolling internally.
    func updatePlacesLensHeight() {
        let rowHeight: CGFloat = 72
        let chrome: CGFloat = 4 + 36 + 6 + 36 + 6
        let height = chrome + max(CGFloat(placesLensRows.count) * rowHeight, 120)
        placesLensHeightConstraint?.constant = height
        view.layoutIfNeeded()
    }
}

// MARK: - Table

extension ProfileViewController {

    func placesLensNumberOfRows() -> Int {
        placesLensRows.count
    }

    func placesLensCell(for indexPath: IndexPath, in tableView: UITableView) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "ProfilePlacesLensCell", for: indexPath
        ) as? QuickAccessPlaceCell ?? QuickAccessPlaceCell(style: .default, reuseIdentifier: "ProfilePlacesLensCell")

        let place = placesLensRows[indexPath.row]
        // City as the secondary line: when you're looking across every circle
        // at once, where a place is matters more than which circle it sits in.
        // Once we know where you are, the nearby ones say how near.
        var subtitle = place.lensCity
        if let origin = placesLensOrigin,
           let coordinate = place.location?.clLocation {
            let metres = origin.distance(from: coordinate)
            // Only worth showing when it's actionable. A place 400 miles away
            // is "in Pittsburgh", not "643 km" — the number adds nothing.
            if metres < 80_000 {
                let distance = metres < 1_000
                    ? String(format: "%.0f m", metres)
                    : String(format: "%.1f km", metres / 1_000)
                subtitle = [subtitle, distance].compactMap { $0 }.joined(separator: " · ")
            }
        }

        cell.configure(with: place, isSelected: false, distanceText: subtitle)
        return cell
    }

    func placesLensDidSelect(_ indexPath: IndexPath) {
        guard indexPath.row < placesLensRows.count else { return }
        let place = placesLensRows[indexPath.row]
        let detailVC = PlaceDetailViewController(place: place)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - Location anchor

/// Fetches a single location fix and hands it back.
///
/// Kept separate from the view controller so nothing here can collide with the
/// map's own location handling, and so the manager stays retained for the
/// lifetime of the request — a `CLLocationManager` that goes out of scope
/// before its callback simply never fires.
final class OneShotLocationProvider: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var completion: ((CLLocation?) -> Void)?
    private var isRunning = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Calls back with a fix, or nil if permission isn't already granted.
    /// Never prompts — this is opportunistic ordering, not a feature worth
    /// interrupting somebody for.
    func requestLocation(_ completion: @escaping (CLLocation?) -> Void) {
        let status = CLLocationManager.authorizationStatus()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            completion(nil)
            return
        }

        // A cached fix is good enough for ranking cities; skip the round trip.
        if let cached = manager.location {
            completion(cached)
            return
        }

        guard !isRunning else { return }
        isRunning = true
        self.completion = completion
        manager.requestLocation()
    }

    private func finish(_ location: CLLocation?) {
        isRunning = false
        let callback = completion
        completion = nil
        callback?(location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.debug("Places lens location unavailable: \(error.localizedDescription)")
        finish(nil)
    }
}
