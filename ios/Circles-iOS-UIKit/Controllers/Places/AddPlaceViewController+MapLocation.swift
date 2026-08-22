import UIKit
import MapKit
import CoreLocation
import PhotosUI

// Map view and location-manager delegates for AddPlaceViewController. Extracted from the main controller (Wave 4).

// MARK: - CLLocationManagerDelegate

extension AddPlaceViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        userLocation = location

        // Zoom in close to the user - they're most likely standing at the
        // place they want to add, and POI labels only render at street-level zoom
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 300,
            longitudinalMeters: 300
        )
        
        // Use dispatch to ensure map renders properly
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.mapView.setRegion(region, animated: true)
            
            // Search for coffee shops if this is the first location update
            if !self.hasPerformedInitialSearch {
                self.hasPerformedInitialSearch = true
                // Small delay to ensure map has finished animating
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.searchNearbyPlaces(query: "coffee shop cafe")
                }
            }
        }
        
        // Stop updating
        manager.stopUpdatingLocation()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            // Also try to get current location immediately
            if let location = manager.location {
                locationManager(manager, didUpdateLocations: [location])
            }
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // This is the old delegate method, keeping for backward compatibility
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location error occurred - could show alert if needed
    }
}

// MARK: - Map Helpers

extension AddPlaceViewController {
    @objc func zoomToCurrentLocation() {
        guard let location = userLocation else {
            // Request location if not available
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
            return
        }
        
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 300,
            longitudinalMeters: 300
        )
        mapView.setRegion(region, animated: true)
    }

    func scrollToFormTop() {
        // Calculate the offset to show the form nicely
        let formY = formContainer.frame.origin.y - 20 // Add some padding
        let maxOffset = scrollView.contentSize.height - scrollView.bounds.height
        let targetOffset = min(formY, maxOffset)
        
        // Animate scroll to show form
        scrollView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: true)
    }
    
    func searchNearbyPlaces(query: String? = nil) {
        // Only search if we're not already searching
        guard !isSearchingNearby else { return }
        
        isSearchingNearby = true
        let region = mapView.region
        
        // Create search request for points of interest
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query ?? "restaurant cafe bar shop attraction" // Use provided query or default
        request.region = region
        request.resultTypes = [.pointOfInterest]
        
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self else { return }
            
            if let response = response {
                // Clear existing annotations except user location
                let annotationsToRemove = self.mapView.annotations.filter { !($0 is MKUserLocation) }
                self.mapView.removeAnnotations(annotationsToRemove)
                
                // Add annotations for each result
                for item in response.mapItems {
                    let annotation = PlaceSearchAnnotation()
                    annotation.coordinate = item.placemark.coordinate
                    annotation.title = item.name
                    annotation.subtitle = item.placemark.title
                    annotation.mapItem = item
                    
                    self.mapView.addAnnotation(annotation)
                }
            }
            
            self.isSearchingNearby = false
        }
    }
}

// MARK: - MKMapViewDelegate

extension AddPlaceViewController: MKMapViewDelegate {
    @available(iOS 16.0, *)
    func handlePOISelection(_ featureAnnotation: MKMapFeatureAnnotation) {
        let poiName = featureAnnotation.title ?? "Unknown Place"
        let poiSubtitle = featureAnnotation.subtitle ?? ""
        let coordinate = featureAnnotation.coordinate
        resetRatingCollection()

        // This tap selected a POI — the deferred manual-location fallback
        // scheduled by handleMapTap for the same physical tap must not also
        // run. It never got cancelled before, so every POI tap ALSO selected
        // the venue nearest the raw tap point 0.35s later, and the two async
        // form-fills raced (wrong photo under the right name).
        pendingManualMapTap?.cancel()
        pendingManualMapTap = nil

        // Dedup: the same selection can arrive via both didSelect variants
        if lastHandledPOIName == poiName,
           let lastTime = lastPOISelectionTime,
           Date().timeIntervalSince(lastTime) < 1.0 {
            Logger.debug("🏪 POI selection deduped: \(poiName)")
            return
        }
        lastHandledPOIName = poiName
        lastPOISelectionTime = Date()

        Logger.debug("🏪 POI selected: \(poiName)")
        Logger.debug("📍 POI subtitle: \(poiSubtitle)")
        Logger.debug("📍 POI coordinate: \(coordinate.latitude), \(coordinate.longitude)")
        
        // Enable form first
        enableManualEntry()
        
        // Extract POI data without saving to backend
        AppleMapsService.shared.extractPOIData(
            from: featureAnnotation
        ) { [weak self] result in
            switch result {
            case .success(let poiData):
                DispatchQueue.main.async {
                    // Fill form with POI details (without saving to backend)
                    self?.nameTextField.text = poiData.name
                    self?.addressTextView.text = poiData.address
                    self?.selectedCategory = poiData.category
                    self?.updateCategoryButtonTitle()
                    
                    // Store additional data for later use when saving
                    self?.currentPOIData = poiData
                    
                    // Update location
                    self?.selectedLocation = coordinate
                    
                    // Add marker to map, titled with the venue (not the
                    // generic green "Selected Location" address pin)
                    self?.addSelectedLocationPin(at: coordinate, title: poiData.name, subtitle: "Venue selected", category: poiData.category)
                    
                    // Center map on selected location
                    let region = MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: 500,
                        longitudinalMeters: 500
                    )
                    self?.mapView.setRegion(region, animated: true)
                    
                    // Deselect the POI annotation
                    self?.mapView.deselectAnnotation(featureAnnotation, animated: true)
                    
                    // Scroll to show form
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self?.scrollToFormTop()
                    }

                    // Attach googlePlaceId + photos — our own database first,
                    // Google only for venues nobody has saved yet
                    let placeName = poiData.name
                    if !placeName.isEmpty {
                        self?.fetchPlaceAssets(
                            name: placeName,
                            coordinate: coordinate,
                            address: poiData.address
                        )
                    }
                }
            case .failure(let error):
                Logger.debug("❌ Failed to convert POI to place: \(error)")
                // Fall back to basic info
                DispatchQueue.main.async {
                    self?.nameTextField.text = poiName
                    self?.addressTextView.text = poiSubtitle
                    self?.selectedLocation = coordinate
                    
                    // Add marker
                    self?.clearPreviousAnnotations()
                    let annotation = MKPointAnnotation()
                    annotation.coordinate = coordinate
                    annotation.title = poiName
                    self?.mapView.addAnnotation(annotation)
                    
                    // Center map
                    let region = MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: 500,
                        longitudinalMeters: 500
                    )
                    self?.mapView.setRegion(region, animated: true)
                    
                    self?.mapView.deselectAnnotation(featureAnnotation, animated: true)
                    
                    // Scroll to form
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self?.scrollToFormTop()
                    }

                    // Attach googlePlaceId + photos even in the fallback case
                    if !poiName.isEmpty {
                        self?.fetchPlaceAssets(
                            name: poiName,
                            coordinate: coordinate,
                            address: poiSubtitle
                        )
                    }
                }
            }
        }
    }
    
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        // Cancel previous timer
        mapRegionTimer?.invalidate()
        
        // Don't auto-search if user has searched for a category, is searching, or is filling form
        guard !hasSearchedCategory && searchResultsTableView.isHidden && !isFillingForm else { return }
        
        // Start new timer to search after user stops moving the map
        mapRegionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.searchNearbyPlaces()
        }
    }
    
    /// iOS 16+ annotation-based selection callback. Map feature (POI) selections
    /// can arrive through this variant instead of the view-based one, so both
    /// forward to the same handler (deduped inside handlePOISelection).
    @available(iOS 16.0, *)
    func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
        pendingManualMapTap?.cancel()
        if let featureAnnotation = annotation as? MKMapFeatureAnnotation {
            handlePOISelection(featureAnnotation)
        }
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        // Any annotation selection consumes the tap — the manual fallback
        // must not fire on top of it
        pendingManualMapTap?.cancel()
        pendingManualMapTap = nil
        // A selection means this tap wasn't an empty-map tap - stop the manual
        // handler from wiping the form
        pendingManualMapTap?.cancel()

        // Handle POI selection for iOS 16+
        if #available(iOS 16.0, *) {
            if let featureAnnotation = view.annotation as? MKMapFeatureAnnotation {
                handlePOISelection(featureAnnotation)
                return
            }
        }

        guard let placeAnnotation = view.annotation as? PlaceSearchAnnotation else { return }
        
        // Skip user location and "Selected Location" markers
        if view.annotation is MKUserLocation || placeAnnotation.title == "Selected Location" {
            return
        }
        
        let name = placeAnnotation.title ?? "Unknown Place"
        Logger.debug("🗺️ Map annotation selected: \(name)")
        Logger.debug("🗺️ Annotation source: \(hasSearchedCategory ? "category search" : "regular search")")
        
        // Check if we have a mapItem (from Apple Maps search)
        if let mapItem = placeAnnotation.mapItem {
            Logger.debug("✅ Found map item, filling form immediately")
            Logger.debug("🗺️ Map item details: name=\(mapItem.name ?? ""), placemark=\(mapItem.placemark)")
            
            // Enable form first to ensure it's ready
            enableManualEntry()
            
            // Small delay to ensure form is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                // Immediately fill the form without confirmation popup
                self?.fillFormWithMapItem(mapItem)
                
                // Scroll to show the form after filling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.scrollToFormTop()
                }
            }
        }
        // Check if we have a Google Place ID
        else if let placeId = placeAnnotation.placeId {
            Logger.debug("✅ Found Google place ID, loading details")
            
            // Enable form first
            enableManualEntry()
            
            // Small delay to ensure form is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                // Load and fill form without confirmation popup
                self?.loadAndFillFormWithGooglePlace(placeId: placeId, markerTitle: name)
                
                // Scroll to show the form
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.scrollToFormTop()
                }
            }
        } else {
            Logger.debug("⚠️ No map item or place ID found for annotation")
        }
        
        // Keep the annotation selected to show the callout
        // The info button will still work for users who want to use it
    }
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Skip user location
        if annotation is MKUserLocation {
            return nil
        }
        
        guard let placeAnnotation = annotation as? PlaceSearchAnnotation else {
            return nil
        }
        
        let identifier = "PlaceSearchAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
            annotationView?.isEnabled = true  // Ensure it's enabled for selection
            
            // Add detail button (optional - users can still use it if they prefer)
            let detailButton = UIButton(type: .detailDisclosure)
            annotationView?.rightCalloutAccessoryView = detailButton
        } else {
            annotationView?.annotation = annotation
            annotationView?.isEnabled = true  // Ensure it's enabled
        }
        
        // Customize appearance
        if let markerView = annotationView {
            if let category = placeAnnotation.category {
                // Venue selection: preview the category color + glyph the
                // saved place will have on the map
                markerView.markerTintColor = category.color
                markerView.glyphImage = UIImage(systemName: category.systemIconName)
            } else if placeAnnotation.isTemporary && placeAnnotation.title == "Selected Location" {
                // Green = manual location pin; venue selections carry their
                // category so users can tell a venue save from an address
                markerView.markerTintColor = .systemGreen
                markerView.glyphImage = nil
            } else {
                markerView.markerTintColor = Constants.Colors.primary
                markerView.glyphImage = nil
            }
        }
        
        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let placeAnnotation = view.annotation as? PlaceSearchAnnotation else { return }
        
        let name = placeAnnotation.title ?? "Unknown Place"
        Logger.debug("ℹ️ Info button tapped: \(name)")
        
        // For "Selected Location" annotations, the form is already filled
        if name == "Selected Location" {
            return
        }
        
        // Since we now handle selection in didSelect, this is just a backup
        // or for users who prefer to use the info button
        Logger.debug("ℹ️ Form should already be populated from didSelect")
        
        // Scroll to form if it's not visible
        scrollToFormTop()
    }
    
}
