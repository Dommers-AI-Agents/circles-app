import UIKit
import CoreLocation

// Navigation destinations shared by the Activity tab, deep links and
// notification taps — they resolve against the home's loaded circles and
// places. The feed itself lives in HomeActivityFeedViewController.

// MARK: - Navigation from Notifications
extension CirclesHomeViewController {
    func scrollToTop() {
        DispatchQueue.main.async {
            self.scrollView.setContentOffset(.zero, animated: true)
            // The activity table scrolls independently of the outer scroll
            // view — reset it too so a Home re-tap always lands at the top
            self.activityTab.scrollToTop()
        }
    }
    
    /// Tab-bar Home re-tap: return the content segment to the Activity tab
    /// (from Moments/Specials) so Home always opens on Activity.
    func resetContentTabToActivity() {
        guard contentSegmentedControl.selectedSegmentIndex != 0 else { return }
        contentSegmentedControl.selectedSegmentIndex = 0
        contentSegmentChanged()
    }
    
    /// Tab-bar Home re-tap: return the map to its original state — no
    /// connection or category filter, framed on the default region, and back
    /// to map (not list) view.
    func resetMapToDefault() {
        resetPlacesListToMap()

        // An active search is a filter too — resetChipFilters below clears the
        // map's copy of the query, so the bar/overlay must not stay behind
        // claiming the pins are filtered.
        if isSearching {
            searchBarCancelButtonClicked(searchBar)
        }

        // Chip filters (category group + region) live inside the embedded map.
        mapViewController?.resetChipFilters()

        // Original load state is "Everyone" (nil) — the map header opens on your
        // network scope, All Categories · All Places.
        if selectedConnectionId != nil || selectedCategory != nil {
            selectedCategory = nil
            selectConnection(id: nil, user: nil)
        } else {
            // Nothing filtered - just re-frame the default region (the user
            // may have panned or zoomed away)
            mapViewController?.adjustMapRegion()
        }
    }
    
    /// Venue offer/announcement activities target the canonical venue record
    /// (globalPlaceId), not a personal save doc — resolve it the same way the
    /// Specials tab does and open the place page
    func navigateToGlobalPlace(withId globalPlaceId: String, showComments: Bool = false) {
        let loading = AlertPresenter.showLoading(message: "Loading place...", from: self)
        GlobalPlaceService.shared.getGlobalPlace(id: globalPlaceId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let response):
                        let place = response.bestDetailPlace()
                        let detailVC = PlaceDetailViewController(place: place)
                        detailVC.showCommentsOnAppear = showComments
                        self.navigationController?.pushViewController(detailVC, animated: true)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
    }
    
    func navigateToCircle(withId circleId: String) {
        // Find the circle in our data
        guard let circle = circles.first(where: { $0.id == circleId }) else {
            // If circle not found, try to load it
            loadCircleAndNavigate(circleId: circleId)
            return
        }
        
        // Navigate to circle detail
        let detailVC = CircleDetailViewController(circle: circle)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func loadCircleAndNavigate(circleId: String) {
        // Show loading
        let loadingAlert = UIAlertController(title: "Loading", message: "Loading circle...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        CircleService.shared.fetchCircleById(id: circleId) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let circle):
                        let detailVC = CircleDetailViewController(circle: circle)
                        self.navigationController?.pushViewController(detailVC, animated: true)
                    case .failure(let error):
                        let alert = UIAlertController(
                            title: "Error",
                            message: "Failed to load circle: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    func navigateToPlace(withId placeId: String, showComments: Bool = false) {
        // Try to find the place in our loaded data first
        if let place = allPlaces.first(where: { $0.id == placeId }) {
            // Find the circle for this place
            if let circle = circles.first(where: { $0.places?.contains(placeId) == true }) {
                let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
                placeDetailVC.showCommentsOnAppear = showComments
                navigationController?.pushViewController(placeDetailVC, animated: true)
            } else if let networkCircle = networkCircles.first(where: { $0.places?.contains(placeId) == true }) {
                let placeDetailVC = PlaceDetailViewController(place: place, circle: networkCircle)
                placeDetailVC.showCommentsOnAppear = showComments
                navigationController?.pushViewController(placeDetailVC, animated: true)
            } else {
                // No circle membership loaded (viewport-fetched network
                // places usually aren't in any local circle array) — the tap
                // used to fall through HERE and silently do nothing
                let placeDetailVC = PlaceDetailViewController(place: place)
                placeDetailVC.showCommentsOnAppear = showComments
                navigationController?.pushViewController(placeDetailVC, animated: true)
            }
        } else {
            // If not found, load the place
            loadPlaceAndNavigate(placeId: placeId, showComments: showComments)
        }
    }
    
    func navigateToCheckInPlace(activity: Activity) {
        // First check if we have the place ID and can find it in our loaded data
        if let placeId = activity.metadata?.placeId,
           let place = allPlaces.first(where: { $0.id == placeId }) {
            // Found the place in our data, navigate normally
            if let circle = circles.first(where: { $0.places?.contains(placeId) == true }) {
                let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
                navigationController?.pushViewController(placeDetailVC, animated: true)
            } else if let networkCircle = networkCircles.first(where: { $0.places?.contains(placeId) == true }) {
                let placeDetailVC = PlaceDetailViewController(place: place, circle: networkCircle)
                navigationController?.pushViewController(placeDetailVC, animated: true)
            } else {
                // Place exists but not in a circle (floating place), still show it
                let placeDetailVC = PlaceDetailViewController(place: place, circle: nil)
                navigationController?.pushViewController(placeDetailVC, animated: true)
            }
        } else if let placeId = activity.metadata?.placeId {
            // Have a place ID but not in our data, try to load it
            // But if it fails, fall back to creating from metadata
            PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let place):
                        // Successfully loaded the place
                        let placeDetailVC = PlaceDetailViewController(place: place, circle: nil)
                        self?.navigationController?.pushViewController(placeDetailVC, animated: true)
                    case .failure:
                        // Failed to load, create from metadata
                        self?.navigateToCheckInPlaceFromMetadata(activity: activity)
                    }
                }
            }
        } else {
            // No place ID, create from metadata
            navigateToCheckInPlaceFromMetadata(activity: activity)
        }
    }
    
    func navigateToCheckInPlaceFromMetadata(activity: Activity) {
        // Create a temporary place from check-in metadata
        guard let metadata = activity.metadata else {
            showError("Unable to load place details for this check-in")
            return
        }
        
        // Determine place category
        let categoryString = metadata.placeCategory ?? "other"
        let category = PlaceCategory(rawValue: categoryString) ?? .other
        
        // Create coordinate if we have location data
        var coordinate: CLLocationCoordinate2D?
        if let lat = metadata.latitude, let lng = metadata.longitude {
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        
        // Create GeoLocation from coordinate
        var geoLocation: GeoLocation? = nil
        if let coord = coordinate {
            geoLocation = GeoLocation(
                type: "Point",
                coordinates: [coord.longitude, coord.latitude]
            )
        }
        
        // Create a temporary place object
        let tempPlace = Place(
            id: activity.metadata?.placeId ?? UUID().uuidString,
            name: activity.targetName,
            description: nil,
            address: metadata.placeAddress ?? "",
            location: geoLocation,
            website: nil,
            phone: nil,
            googlePlaceId: nil,
            photos: metadata.placePhoto != nil ? [metadata.placePhoto!] : nil,
            videos: nil,
            category: category,
            customCategoryId: nil,
            subcategory: nil,
            rating: nil,
            userRatingsTotal: nil,
            notes: metadata.message,
            privateNotes: nil,
            publicNotes: nil,
            tags: nil,
            reviews: nil,
            openingHours: nil,
            priceLevel: nil,
            likes: nil,
            likesCount: nil,
            commentsCount: 0,
            circleId: metadata.circleId ?? "",
            addedBy: activity.actorId,
            addedByUser: nil,
            privacy: .public,
            createdAt: Date(),
            updatedAt: Date(),
            isNew: true
        )
        
        // Navigate to place detail with the temporary place
        let placeDetailVC = PlaceDetailViewController(place: tempPlace, circle: nil)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
    
    func loadPlaceAndNavigate(placeId: String, showComments: Bool = false) {
        // Show loading
        let loadingAlert = UIAlertController(title: "Loading", message: "Loading place...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        PlaceService.shared.fetchPlaceById(id: placeId) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let place):
                        // We need to find the circle
                        guard let circleId = place.circleId else {
                            let alert = UIAlertController(
                                title: "Error",
                                message: "Place has no associated circle",
                                preferredStyle: .alert
                            )
                            alert.addAction(UIAlertAction(title: "OK", style: .default))
                            self.present(alert, animated: true)
                            return
                        }
                        CircleService.shared.fetchCircleById(id: circleId) { circleResult in
                            DispatchQueue.main.async {
                                switch circleResult {
                                case .success(let circle):
                                    let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
                                    placeDetailVC.showCommentsOnAppear = showComments
                                    self.navigationController?.pushViewController(placeDetailVC, animated: true)
                                case .failure:
                                    // Show error
                                    let alert = UIAlertController(
                                        title: "Error",
                                        message: "Failed to load place details",
                                        preferredStyle: .alert
                                    )
                                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                                    self.present(alert, animated: true)
                                }
                            }
                        }
                    case .failure(let error):
                        let alert = UIAlertController(
                            title: "Error",
                            message: "Failed to load place: \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            }
        }
    }
}
