import UIKit
import MapKit
import CoreLocation
import PhotosUI

// Public prefill entry points (search + check-ins) for AddPlaceViewController. Extracted from the main controller (Wave 4).

// MARK: - Public Methods for Prefilling

extension AddPlaceViewController {
    /// Prefills the search bar with a place name and triggers search
    func prefillSearchWithPlace(name: String, coordinate: CLLocationCoordinate2D? = nil) {
        // Wait for view to load if needed
        guard isViewLoaded else {
            // Store for later use after view loads
            DispatchQueue.main.async { [weak self] in
                self?.prefillSearchWithPlace(name: name, coordinate: coordinate)
            }
            return
        }
        
        // Set search text
        searchBar.text = name
        
        // Store the coordinate for auto-selection
        self.selectedLocation = coordinate
        
        // If coordinate provided, center map on it
        if let coordinate = coordinate {
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 1000,
                longitudinalMeters: 1000
            )
            mapView.setRegion(region, animated: true)
            
            // Add a temporary annotation to show the location
            let tempAnnotation = PlaceSearchAnnotation()
            tempAnnotation.coordinate = coordinate
            tempAnnotation.title = name
            tempAnnotation.isTemporary = true
            mapView.addAnnotation(tempAnnotation)
        }
        
        // Trigger search after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            // Perform the search
            self.performAppleMapsSearch(name)
            
            // After search completes, directly trigger the search and fill form
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // If we have a coordinate, search for the place and fill form
                if let coordinate = coordinate, !name.isEmpty {
                    // Create a search request for the specific place
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = name
                    request.region = MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: 200, // Small radius for precise search
                        longitudinalMeters: 200
                    )
                    
                    let search = MKLocalSearch(request: request)
                    search.start { [weak self] response, error in
                        guard let self = self else { return }
                        
                        if let error = error {
                            Logger.debug("❌ POI search error: \(error.localizedDescription)")
                            // Still enable form for manual entry
                            self.enableManualEntry()
                            return
                        }
                        
                        // Find the closest match to our POI
                        if let mapItems = response?.mapItems {
                            let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                            let closestItem = mapItems.min(by: { item1, item2 in
                                let dist1 = targetLocation.distance(from: CLLocation(
                                    latitude: item1.placemark.coordinate.latitude,
                                    longitude: item1.placemark.coordinate.longitude
                                ))
                                let dist2 = targetLocation.distance(from: CLLocation(
                                    latitude: item2.placemark.coordinate.latitude,
                                    longitude: item2.placemark.coordinate.longitude
                                ))
                                return dist1 < dist2
                            })
                            
                            if let mapItem = closestItem {
                                Logger.debug("✅ Found POI match: \(mapItem.name ?? name)")
                                
                                DispatchQueue.main.async {
                                    // Enable form and fill it
                                    self.enableManualEntry()
                                    self.fillFormWithMapItem(mapItem)
                                    
                                    // Update map to show the place
                                    self.showBothUserAndPlace(placeCoordinate: mapItem.placemark.coordinate)
                                    
                                    // Add annotation for the selected place
                                    let annotation = PlaceSearchAnnotation()
                                    annotation.coordinate = mapItem.placemark.coordinate
                                    annotation.title = mapItem.name ?? name
                                    annotation.subtitle = self.formatAddress(for: mapItem.placemark)
                                    annotation.mapItem = mapItem
                                    
                                    // Remove previous annotations except user location and temporary
                                    let annotationsToRemove = self.mapView.annotations.filter { 
                                        !($0 is MKUserLocation) && 
                                        !(($0 as? PlaceSearchAnnotation)?.isTemporary ?? false) 
                                    }
                                    self.mapView.removeAnnotations(annotationsToRemove)
                                    
                                    self.mapView.addAnnotation(annotation)
                                    self.annotations = [annotation]
                                    
                                    // Select the annotation to show callout
                                    self.mapView.selectAnnotation(annotation, animated: true)
                                    
                                    // Scroll to form
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        self.scrollToFormTop()
                                    }
                                }
                            } else {
                                Logger.debug("⚠️ No matching POI found nearby")
                                self.enableManualEntry()
                            }
                        }
                    }
                } else if !name.isEmpty {
                    // No coordinate, just select first search result
                    if self.searchResults.count > 0 {
                        self.selectSearchResult(self.searchResults[0])
                    }
                }
            }
        }
    }
    
    // MARK: - Public Methods
    @available(iOS 16.0, *)
    func configureWithPOI(_ featureAnnotation: MKMapFeatureAnnotation) {
        // Extract POI information
        let poiName = featureAnnotation.title ?? "Unknown Place"
        let coordinate = featureAnnotation.coordinate
        
        // Perform a local search to get more details about the POI
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = poiName
        searchRequest.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
        )
        
        let search = MKLocalSearch(request: searchRequest)
        search.start { [weak self] response, error in
            guard let self = self else { return }
            
            if let error = error {
                Logger.debug("❌ Error searching for POI: \(error)")
                return
            }
            
            // Find the closest matching result
            if let mapItems = response?.mapItems,
               let closestItem = mapItems.min(by: { item1, item2 in
                   let dist1 = CLLocation(
                       latitude: coordinate.latitude,
                       longitude: coordinate.longitude
                   ).distance(from: CLLocation(
                       latitude: item1.placemark.coordinate.latitude,
                       longitude: item1.placemark.coordinate.longitude
                   ))
                   let dist2 = CLLocation(
                       latitude: coordinate.latitude,
                       longitude: coordinate.longitude
                   ).distance(from: CLLocation(
                       latitude: item2.placemark.coordinate.latitude,
                       longitude: item2.placemark.coordinate.longitude
                   ))
                   return dist1 < dist2
               }) {
                DispatchQueue.main.async {
                    // Fill the form with the map item details
                    self.fillFormWithMapItem(closestItem)
                    
                    // Update the search bar text
                    self.searchBar.text = closestItem.name ?? poiName
                    
                    // Scroll to show the form
                    self.scrollToFormTop()
                }
            }
        }
    }
    
    // MARK: - Circle Management
    
    func loadUserCircles() {
        CircleService.shared.fetchUserCircles { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let circles):
                self.applyUserCircles(circles)
            case .failure(let error):
                Logger.debug("❌ Failed to load circles: \(error)")
                // Still try to show the circle name if we have the ID
                DispatchQueue.main.async {
                    self.circleButton.setTitle("Loading...", for: .normal)
                }
            }
        }
    }

    func applyUserCircles(_ circles: [Circle]) {
        // Keep the server's order — /circles/me already returns circles in the
        // user's own arrangement (the drag-to-reorder order from their profile),
        // so every circle list in the app reads the same way.
        userCircles = circles

        // Find and set the current circle
        if let currentCircle = userCircles.first(where: { $0.id == selectedCircleId }) {
            selectedCircle = currentCircle
            DispatchQueue.main.async {
                self.circleButton.setTitle(currentCircle.name, for: .normal)
            }
        } else if let firstCircle = circles.first {
            // Fallback to first circle if the selected one is not found
            selectedCircle = firstCircle
            selectedCircleId = firstCircle.id
            DispatchQueue.main.async {
                self.circleButton.setTitle(firstCircle.name, for: .normal)
            }
        }
    }
    
    // MARK: - Navigation Helpers
    func navigateToCircleDetail() {
        // Reached only after a successful save - remember the circle so the home
        // quick-add button can skip the circle picker next time
        UserDefaults.standard.set(selectedCircleId, forKey: Self.lastUsedCircleKey)

        // Check if this view controller is being presented modally
        let isModal = self.presentingViewController != nil
        
        if isModal {
            // If presented modally (e.g., from PlaceDetailViewController when adding from another's circle)
            // Just dismiss the modal and let the presenting controller handle its own UI
            self.dismiss(animated: true) {
                // Post notification that place was successfully added
                NotificationCenter.default.post(
                    name: Notification.Name("PlaceAddedToCircle"),
                    object: nil,
                    userInfo: ["circleId": self.selectedCircleId]
                )
            }
        } else {
            // Swap AddPlace for CircleDetail in the nav stack
            let pushDetail: (Circle) -> Void = { [weak self] circle in
                guard let self = self, let navigationController = self.navigationController else { return }
                let circleDetailVC = CircleDetailViewController(circle: circle)
                var viewControllers = navigationController.viewControllers
                if viewControllers.last is AddPlaceViewController {
                    viewControllers.removeLast()
                }
                viewControllers.append(circleDetailVC)
                navigationController.setViewControllers(viewControllers, animated: true)
            }

            // The circle the user picked is already in hand — navigating
            // through a fetch round-trip here was half the "why is it slow
            // after saving" delay (the other half is CircleDetail's own place
            // fetch). Only fall back to the network when we somehow don't
            // hold the object (e.g. quick-add preselected by id only).
            if let circle = selectedCircle, circle.id == selectedCircleId {
                pushDetail(circle)
                return
            }

            CircleService.shared.fetchCircleById(id: selectedCircleId) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch result {
                    case .success(let circle):
                        pushDetail(circle)
                    case .failure(let error):
                        Logger.debug("❌ Failed to fetch circle for navigation: \(error)")
                        // Fallback: leave the screen (handles modal too)
                        self.closeAddPlaceScreen()
                    }
                }
            }
        }
    }
}

// MARK: - Public Methods for Prefilling from Check-ins
extension AddPlaceViewController {
    /// Prefills the form with data from an existing place (e.g., from check-in)
    func prefillWithPlace(_ place: Place) {
        // Wait for view to load if needed
        guard isViewLoaded else {
            DispatchQueue.main.async { [weak self] in
                self?.prefillWithPlace(place)
            }
            return
        }
        
        // Set search text
        searchBar.text = place.name
        
        // Pre-fill notes if available
        if let notes = place.notes, !notes.isEmpty {
            // A prefilled caption is the saver's own annotation now
            privateNotesTextView.text = notes
            privateNotesTextView.textColor = .label
        }
        
        // Set category
        selectedCategory = place.category
        categoryButton.setTitle(selectedCategory.displayName, for: .normal)
        
        // If we have location data, perform search with coordinates
        if let location = place.location?.clLocation {
            let coordinate = location.coordinate
            
            // Store the coordinate
            self.selectedLocation = coordinate
            
            // Center map on the location
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            mapView.setRegion(region, animated: true)
            
            // Perform search with name and location
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                
                // Create a search request for the specific place
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = place.name
                request.region = MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 500, // Wider search radius
                    longitudinalMeters: 500
                )
                
                let search = MKLocalSearch(request: request)
                search.start { [weak self] response, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        Logger.debug("❌ Place search error: \(error.localizedDescription)")
                        // Still enable form for manual entry with existing data
                        DispatchQueue.main.async {
                            self.enableManualEntry()
                            self.nameTextField.text = place.name
                            self.addressTextView.text = place.address
                        }
                        return
                    }
                    
                    // Find the best match
                    if let mapItems = response?.mapItems, !mapItems.isEmpty {
                        // Look for exact name match first
                        let exactMatch = mapItems.first { item in
                            item.name?.lowercased() == place.name.lowercased()
                        }
                        
                        // Or find closest by distance
                        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        let closestItem = exactMatch ?? mapItems.min(by: { item1, item2 in
                            let dist1 = targetLocation.distance(from: CLLocation(
                                latitude: item1.placemark.coordinate.latitude,
                                longitude: item1.placemark.coordinate.longitude
                            ))
                            let dist2 = targetLocation.distance(from: CLLocation(
                                latitude: item2.placemark.coordinate.latitude,
                                longitude: item2.placemark.coordinate.longitude
                            ))
                            return dist1 < dist2
                        })
                        
                        if let mapItem = closestItem {
                            Logger.debug("✅ Found place match: \(mapItem.name ?? place.name)")
                            
                            DispatchQueue.main.async {
                                // Fill form with MapKit data (which will trigger Google Photos search)
                                self.fillFormWithMapItem(mapItem)
                                
                                // Scroll to form after a delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    self.scrollToFormTop()
                                }
                            }
                        } else {
                            // No match found, fill manually
                            DispatchQueue.main.async {
                                self.enableManualEntry()
                                self.nameTextField.text = place.name
                                self.addressTextView.text = place.address
                            }
                        }
                    } else {
                        // No results, fill manually
                        DispatchQueue.main.async {
                            self.enableManualEntry()
                            self.nameTextField.text = place.name
                            self.addressTextView.text = place.address
                        }
                    }
                }
            }
        } else {
            // No location data, just search by name
            performAppleMapsSearch(place.name)
            
            // Enable form for manual entry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.enableManualEntry()
                self.nameTextField.text = place.name
                self.addressTextView.text = place.address
            }
        }
    }
}

