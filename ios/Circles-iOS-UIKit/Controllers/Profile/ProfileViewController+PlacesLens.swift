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
        let groups = PlaceCategoryGroup.present(in: allPlaces.map { $0.category.rawValue })
        placesCategoryChipBar.setGroups(groups, selected: selectedPlacesGroup)

        placesRegionGroups = RegionGrouper.groups(for: allPlaces, origin: nil)
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

    // MARK: Filtering

    /// filterPlaces() applies the chip filters (region group + category group)
    /// alongside the shared ones, refreshes the pins with a zoom-to-fit, and
    /// keeps the distance-sorted list in sync when it's showing.
    func applyPlacesLensFilters() {
        filterPlaces()
    }
}
