import UIKit
import CoreLocation

// MARK: - Map filter chips (the former "Places lens")
//
// A view of every place you've saved, cutting straight across circles.
//
// This began as a separate "Places" list segment, but that duplicated the map's
// own list mode — so the profile is now just Circles and Map, and the lens's
// category + state filter chips live directly above the map. One place to
// filter; the pins, the zoom, and the closest-first list all follow.

extension ProfileViewController {

    // MARK: Setup

    /// Installs the two chip bars into the map's filter container: category
    /// chips (sharing their row with the list toggle) over the state chips.
    func setupPlacesLens() {
        guard placesCategoryChipBar.superview == nil else { return }

        filterContainerView.addSubview(placesCategoryChipBar)
        placesCityChipBar.translatesAutoresizingMaskIntoConstraints = false
        filterContainerView.addSubview(placesCityChipBar)

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

        NSLayoutConstraint.activate([
            placesCategoryChipBar.topAnchor.constraint(equalTo: filterContainerView.topAnchor, constant: 6),
            placesCategoryChipBar.leadingAnchor.constraint(equalTo: filterContainerView.leadingAnchor),
            placesCategoryChipBar.trailingAnchor.constraint(equalTo: mapListChipButton.leadingAnchor, constant: -4),
            placesCategoryChipBar.heightAnchor.constraint(equalToConstant: 36),

            placesCityChipBar.topAnchor.constraint(equalTo: placesCategoryChipBar.bottomAnchor, constant: 4),
            placesCityChipBar.leadingAnchor.constraint(equalTo: filterContainerView.leadingAnchor),
            placesCityChipBar.trailingAnchor.constraint(equalTo: filterContainerView.trailingAnchor),
            placesCityChipBar.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    // MARK: Chips

    /// Rebuilds both chip rows from whatever is actually saved, so a filter is
    /// never offered for something that would come back empty.
    ///
    /// Region chips are one per STATE (see RegionGrouper), most places first.
    func refreshPlacesLensChips() {
        // Faceted, like the home map's dropdowns: each bar's options come from
        // the set filtered by the OTHER bar, so picking Hotels re-counts the
        // state chips down to just the hotels ("Rhode Island (2)"), and picking
        // a state narrows the category chips to what's actually there.
        var categoryBase = allPlaces
        if let region = selectedRegionGroup {
            categoryBase = categoryBase.filter { region.contains($0) }
        }
        var groups = PlaceCategoryGroup.present(in: categoryBase.map { $0.category.rawValue })
        // Never hide the active selection — you need its chip to un-pick it.
        if selectedPlacesGroup != .all && !groups.contains(selectedPlacesGroup) {
            groups.append(selectedPlacesGroup)
        }
        placesCategoryChipBar.setGroups(groups, selected: selectedPlacesGroup)

        // Full groups keep filter membership stable; the visible chips below
        // are rebuilt from the category-filtered subset.
        placesRegionGroups = RegionGrouper.groups(for: allPlaces, origin: lensOrigin)

        // First pass has no fix yet: resolve one quietly, and when it lands
        // rebuild so "Near me" takes its place at the front. No permission or
        // no fix is normal — the row simply starts at the states.
        if lensOrigin == nil {
            lensLocationProvider.requestLocation { [weak self] location in
                DispatchQueue.main.async {
                    guard let self = self, let location = location, self.lensOrigin == nil else { return }
                    self.lensOrigin = location
                    self.refreshPlacesLensChips()
                }
            }
        }
        // A stale selection (places changed underneath it) resets to All.
        if selectedRegionGroupId != nil && selectedRegionGroup == nil {
            selectedRegionGroupId = nil
        }

        // Visible region chips: recomputed from the category-filtered subset,
        // so their counts always describe what selecting them would show.
        var regionBase = allPlaces
        if selectedPlacesGroup != .all {
            regionBase = regionBase.filter { selectedPlacesGroup.matches($0.category.rawValue) }
        }
        var facetGroups = RegionGrouper.groups(for: regionBase, origin: lensOrigin)
        if let selectedId = selectedRegionGroupId,
           !facetGroups.contains(where: { $0.id == selectedId }),
           let full = placesRegionGroups.first(where: { $0.id == selectedId }) {
            facetGroups.append(RegionGroup(
                id: full.id, title: full.title, count: 0,
                placeIds: [], centroid: full.centroid
            ))
        }

        var items: [BrowseChipBar.Item] = [BrowseChipBar.Item(id: "__all", title: "All places")]
        items.append(contentsOf: facetGroups.map {
            BrowseChipBar.Item(id: $0.id, title: "\($0.title) (\($0.count))")
        })
        placesCityChipBar.setItems(items, selectedId: selectedRegionGroupId ?? "__all")
    }

    // MARK: Filtering

    /// filterPlaces() applies the chip filters (region group + category group)
    /// alongside the shared ones, refreshes the pins with a zoom-to-fit, and
    /// keeps the distance-sorted list in sync when it's showing. The chips are
    /// re-faceted too, so each bar's counts track the other bar's selection.
    func applyPlacesLensFilters() {
        refreshPlacesLensChips()
        filterPlaces()
    }
}
