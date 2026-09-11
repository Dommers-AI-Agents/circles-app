import UIKit
import CoreLocation

// The save flow for AddPlaceViewController: Save tap → validation →
// duplicate check → staged alerts → place creation (three payload builders,
// each posting PlaceAddedToCircle). Moved verbatim from the core controller
// (Phase 5 step 6); `isSaving`, the saving overlay and begin/endSaving stay
// in the core because extensions can't hold stored state.

extension AddPlaceViewController {
    @objc func addPlaceButtonTapped() {
        guard !isSaving else { return }
        guard let name = nameTextField.text, !name.isEmpty,
              let rawAddress = addressTextView.text, !rawAddress.isEmpty else {
            presentAlert(title: "Error", message: "Please provide a name and address")
            return
        }
        // The address box shows a "📍 X mi from current location" decoration —
        // display-only; it was leaking into the SAVED address ("Indaco …
        // 📍 0 mi from current location" shipped to the server verbatim)
        let address = rawAddress
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("📍") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if we have location data from any source
        let hasLocation = selectedLocation != nil || selectedGooglePlaceDetails != nil || currentPOIData != nil
        
        if !hasLocation {
            // Show alert to user that they need to select a location
            let alert = UIAlertController(
                title: "Location Required",
                message: "Please select a location on the map or search for the place to set its location.",
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "Select on Map", style: .default) { [weak self] _ in
                // Scroll to map and show instruction
                self?.scrollView.setContentOffset(.zero, animated: true)
                self?.presentAlert(title: "Tap on Map", message: "Tap on the map to set the location for this place")
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            present(alert, animated: true)
            return
        }
        
        // The rating prompt runs once, at the moment of commitment: tap a
        // 0–10 pill (or Skip) and the save re-enters this method with
        // hasCollectedRating set. Swiping the prompt away cancels the save.
        if showsRatingPromptOnSave && !hasCollectedRating {
            presentRatingPromptBeforeSave()
            return
        }

        // The form's Review/Comment field posts as a venue comment (visible
        // to anyone who opens the place) right after the save succeeds
        let reviewText = reviewCommentTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingReviewText = reviewText.isEmpty ? nil : reviewText

        let category = selectedCategory

        // Get custom category if "Other" is selected
        let customCategory: String? = (category == .other && selectedSubcategory != nil) ? selectedSubcategory : nil
        let subcategory: String? = (category != .other) ? selectedSubcategory : nil
        
        let description = descriptionTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let privateNotes = privateNotesTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Get privacy setting from segmented control
        let privacy: PlacePrivacy = privacySegmentedControl.selectedSegmentIndex == 0 ? .followCirclePrivacy : .private
        
        // Guard the whole create flow (duplicate check -> create -> navigate)
        // against a second tap; released on every failure/cancel path
        beginSaving()

        // First check for duplicates
        let checkingAlert = UIAlertController(title: "Checking...", message: "Verifying place doesn't already exist", preferredStyle: .alert)
        present(checkingAlert, animated: true)
        
        // Check for duplicate places
        checkForDuplicatePlace(name: name, address: address, googlePlaceId: selectedGooglePlaceDetails?.placeID) { [weak self] duplicatePlace, duplicateCircle in
            DispatchQueue.main.async {
                checkingAlert.dismiss(animated: true) {
                    if let duplicate = duplicatePlace, let circle = duplicateCircle {
                        // Show alert about duplicate
                        let alert = UIAlertController(
                            title: "Similar Place Found",
                            message: "You already have \"\(duplicate.name)\" in your \"\(circle.name)\" circle. What would you like to do?",
                            preferredStyle: .alert
                        )
                        
                        alert.addAction(UIAlertAction(title: "View Place", style: .default) { _ in
                            // Navigate to the circle detail view with the duplicate place
                            self?.navigateToCircleDetail()
                        })
                        
                        alert.addAction(UIAlertAction(title: "Add Anyway", style: .default) { _ in
                            // User wants to add the place despite it being a duplicate
                            self?.proceedWithPlaceCreation(
                                name: name,
                                address: address,
                                description: description,
                                category: category,
                                customCategory: customCategory,
                                subcategory: subcategory,
                                privacy: privacy,
                                privateNotes: privateNotes.isEmpty ? nil : privateNotes,
                                force: true  // User explicitly chose to add despite duplicate
                            )
                        })
                        
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                            self?.endSaving()
                        })

                        self?.present(alert, animated: true)
                    } else {
                        // No duplicate found, proceed with creation
                        self?.proceedWithPlaceCreation(
                            name: name,
                            address: address,
                            description: description,
                            category: category,
                            customCategory: customCategory,
                            subcategory: subcategory,
                            privacy: privacy,
                            privateNotes: privateNotes.isEmpty ? nil : privateNotes,
                        )
                    }
                }
            }
        }
    }
    
    func checkForDuplicatePlace(name: String, address: String, googlePlaceId: String?, completion: @escaping (Place?, Circle?) -> Void) {
        // Get all circles for the user
        CircleService.shared.fetchUserCircles { result in
            switch result {
            case .success(let circles):
                let group = DispatchGroup()
                var duplicatePlace: Place?
                var duplicateCircle: Circle?
                
                // Check each circle for places
                for circle in circles {
                    group.enter()
                    PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { placeResult in
                        defer { group.leave() }
                        
                        if case .success(let places) = placeResult {
                            // Check for duplicate by googlePlaceId first (most accurate)
                            if let googleId = googlePlaceId, !googleId.isEmpty {
                                if let match = places.first(where: { $0.googlePlaceId == googleId }) {
                                    duplicatePlace = match
                                    duplicateCircle = circle
                                    return
                                }
                            }
                            
                            // Check by name and address similarity
                            for place in places {
                                // Exact name match
                                if place.name.lowercased() == name.lowercased() {
                                    // Check if addresses are similar
                                    let placeAddressLower = place.address.lowercased()
                                    let newAddressLower = address.lowercased()
                                    
                                    // Parse address components more intelligently
                                    let placeComponents = placeAddressLower.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
                                    let newComponents = newAddressLower.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
                                    
                                    // Extract key location identifiers (city, state, zip)
                                    // For US addresses, typically: "123 Main St, City, State Zip, Country"
                                    // We want to focus on city and state for differentiation
                                    
                                    // Try to find state abbreviations (2 letters) or zip codes (5 digits)
                                    let statePattern = #"^[a-z]{2}$"#
                                    let zipPattern = #"^\d{5}(-\d{4})?$"#
                                    
                                    var placeState: String? = nil
                                    var placeCity: String? = nil
                                    var placeZip: String? = nil
                                    
                                    var newState: String? = nil
                                    var newCity: String? = nil
                                    var newZip: String? = nil
                                    
                                    // Parse existing place address
                                    for (index, component) in placeComponents.enumerated() {
                                        // Check if it's a state abbreviation
                                        if component.range(of: statePattern, options: .regularExpression) != nil {
                                            placeState = component
                                            // City is usually before state
                                            if index > 0 {
                                                placeCity = placeComponents[index - 1]
                                            }
                                        }
                                        // Check if it's a zip code
                                        if component.range(of: zipPattern, options: .regularExpression) != nil {
                                            placeZip = component
                                        }
                                    }
                                    
                                    // Parse new address
                                    for (index, component) in newComponents.enumerated() {
                                        // Check if it's a state abbreviation
                                        if component.range(of: statePattern, options: .regularExpression) != nil {
                                            newState = component
                                            // City is usually before state
                                            if index > 0 {
                                                newCity = newComponents[index - 1]
                                            }
                                        }
                                        // Check if it's a zip code
                                        if component.range(of: zipPattern, options: .regularExpression) != nil {
                                            newZip = component
                                        }
                                    }
                                    
                                    // If we found states and they're different, it's not a duplicate
                                    if let pState = placeState, let nState = newState, pState != nState {
                                        continue // Not a duplicate, different states
                                    }
                                    
                                    // If we found cities and they're different, it's not a duplicate
                                    if let pCity = placeCity, let nCity = newCity {
                                        // Remove common words like "township", "city", etc. for comparison
                                        let pCityClean = pCity.replacingOccurrences(of: "township", with: "", options: .caseInsensitive)
                                            .replacingOccurrences(of: "city", with: "", options: .caseInsensitive)
                                            .trimmingCharacters(in: .whitespaces)
                                        let nCityClean = nCity.replacingOccurrences(of: "township", with: "", options: .caseInsensitive)
                                            .replacingOccurrences(of: "city", with: "", options: .caseInsensitive)
                                            .trimmingCharacters(in: .whitespaces)
                                        
                                        if pCityClean != nCityClean {
                                            continue // Not a duplicate, different cities
                                        }
                                    }
                                    
                                    // If we found zip codes and they're different, it's not a duplicate
                                    if let pZip = placeZip, let nZip = newZip, pZip != nZip {
                                        continue // Not a duplicate, different zip codes
                                    }
                                    
                                    // If we couldn't determine city/state/zip differences, do a more strict check
                                    // Consider it a duplicate only if addresses are very similar (not just having common words)
                                    if placeAddressLower == newAddressLower {
                                        // Exact address match - definitely a duplicate
                                        duplicatePlace = place
                                        duplicateCircle = circle
                                        return
                                    }
                                    
                                    // Check if street addresses are the same (first component is usually street)
                                    if placeComponents.count > 0 && newComponents.count > 0 {
                                        let placeStreet = placeComponents[0]
                                        let newStreet = newComponents[0]
                                        
                                        // If street addresses are the same AND we couldn't differentiate by city/state/zip
                                        // then it might be a duplicate
                                        if placeStreet == newStreet && placeState == newState && placeCity == newCity {
                                            duplicatePlace = place
                                            duplicateCircle = circle
                                            return
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                group.notify(queue: .main) {
                    completion(duplicatePlace, duplicateCircle)
                }
                
            case .failure:
                // If we can't check for duplicates, allow creation
                completion(nil, nil)
            }
        }
    }
    
    func proceedWithPlaceCreation(name: String, address: String, description: String, 
                                        category: PlaceCategory, customCategory: String?, 
                                        subcategory: String?, privacy: PlacePrivacy,
                                        privateNotes: String?,
                                        force: Bool = false) {
        // Create place
        let loadingAlert = UIAlertController(title: "Creating Place", message: "Please wait...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Check if we have pre-uploaded photos
        Logger.debug("📸 Checking pre-uploaded photos: \(uploadedPhotoUrls.count) available")
        
        // Only prepare photo data if no pre-uploaded photos exist
        var photoData: [Data]? = nil
        if uploadedPhotoUrls.isEmpty && selectedImage != nil {
            Logger.debug("⚠️ No pre-uploaded photos but image exists - this shouldn't happen!")
            // This is a fallback - photos should have been pre-uploaded
            if let image = selectedImage {
                if let imageData = image.jpegData(compressionQuality: 0.6) {
                    photoData = [imageData]
                    Logger.debug("📸 Using fallback photo data")
                }
            }
        }
        
        // Check if we have Google Place details to use
        if let googleDetails = selectedGooglePlaceDetails {
            Logger.debug("🚀 AddPlaceViewController: Creating place with Google details")
            Logger.debug("  Name: \(name)")
            Logger.debug("  GooglePlaceId: \(googleDetails.placeID)")
            Logger.debug("  Has photos: \(googleDetails.photos.count > 0)")
            Logger.debug("  Coordinate: \(googleDetails.coordinate.latitude), \(googleDetails.coordinate.longitude)")
            
            // Check if coordinates are valid
            let isValidCoordinate = googleDetails.coordinate.latitude >= -90 && googleDetails.coordinate.latitude <= 90 &&
                                  googleDetails.coordinate.longitude >= -180 && googleDetails.coordinate.longitude <= 180 &&
                                  !(googleDetails.coordinate.longitude == -180 && googleDetails.coordinate.latitude == -180) &&
                                  !(googleDetails.coordinate.longitude == 0 && googleDetails.coordinate.latitude == 0)
            
            if !isValidCoordinate {
                Logger.debug("⚠️ Google Place has invalid coordinates: \(googleDetails.coordinate.latitude), \(googleDetails.coordinate.longitude)")
                Logger.debug("🔄 Will attempt to geocode the address: \(address)")
                
                // Geocode the address to get valid coordinates
                let geocoder = CLGeocoder()
                geocoder.geocodeAddressString(address) { [weak self] placemarks, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        Logger.debug("❌ Geocoding failed: \(error.localizedDescription)")
                        loadingAlert.dismiss(animated: true) {
                            self.endSaving()
                            self.presentAlert(title: "Location Error",
                                            message: "Unable to determine location for this address. Please select a location on the map.")
                        }
                        return
                    }
                    
                    guard let placemark = placemarks?.first,
                          let location = placemark.location else {
                        Logger.debug("❌ No location found for address")
                        loadingAlert.dismiss(animated: true) {
                            self.endSaving()
                            self.presentAlert(title: "Location Error",
                                            message: "Unable to find location for this address. Please select a location on the map.")
                        }
                        return
                    }
                    
                    Logger.debug("✅ Successfully geocoded address to: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                    
                    // Create place with geocoded coordinates
                    let geoLocation = GeoLocation(
                        type: "Point", 
                        coordinates: [location.coordinate.longitude, location.coordinate.latitude]
                    )
                    
                    self.createPlaceWithGoogleDetails(googleDetails: googleDetails,
                                                    name: name,
                                                    address: address,
                                                    location: geoLocation,
                                                    category: category,
                                                    description: description,
                                                    privateNotes: privateNotes,
                                                    loadingAlert: loadingAlert,
                                                    force: force)
                }
                return
            }
            
            // Coordinates are valid, proceed with normal creation
            let location = GeoLocation(
                type: "Point", 
                coordinates: [googleDetails.coordinate.longitude, googleDetails.coordinate.latitude]
            )
            
            createPlaceWithGoogleDetails(googleDetails: googleDetails,
                                       name: name,
                                       address: address,
                                       location: location,
                                       category: category,
                                       description: description,
                                       privateNotes: privateNotes,
                                       loadingAlert: loadingAlert,
                                       force: force)
        } else if let poiData = currentPOIData {
            // We have POI data but no Google details - use the POI location
            Logger.debug("🚀 Creating place from POI data without Google details")
            Logger.debug("  Name: \(name)")
            Logger.debug("  POI Location: \(poiData.coordinate)")
            
            let location = GeoLocation(
                type: "Point",
                coordinates: [poiData.coordinate.longitude, poiData.coordinate.latitude]
            )
            
            PlaceService.shared.addPlaceFromPOI(
                name: name,
                address: address,
                location: location,
                category: category,
                website: poiData.website,
                phone: poiData.phoneNumber,
                description: description.isEmpty ? nil : description,
                circleId: selectedCircleId,
                notes: privateNotes,
                googlePlaceId: nil,
                preUploadedPhotoUrls: self.uploadedPhotoUrls.isEmpty ? nil : self.uploadedPhotoUrls,
                force: force
            ) { [weak self] result in
                DispatchQueue.main.async {
                    loadingAlert.dismiss(animated: true) {
                        switch result {
                        case .success(let place):
                            Logger.debug("✅ Place created successfully from POI")
                            Logger.debug("📸 DEBUG: Place returned with \(place.photos?.count ?? 0) photos:")
                            if let photos = place.photos {
                                for (index, photoUrl) in photos.enumerated() {
                                    Logger.debug("  Photo \(index + 1): \(photoUrl)")
                                }
                            }
                            Logger.debug("📸 DEBUG: Originally uploaded \(self?.uploadedPhotoUrls.count ?? 0) photos:")
                            if let uploadedUrls = self?.uploadedPhotoUrls {
                                for (index, url) in uploadedUrls.enumerated() {
                                    Logger.debug("  Uploaded \(index + 1): \(url)")
                                }
                            }
                            
                            NotificationCenter.default.post(
                                name: Notification.Name("PlaceAddedToCircle"),
                                object: nil,
                                userInfo: ["circleId": self?.selectedCircleId ?? "", "place": place]
                            )

                            self?.postPendingReviewIfNeeded(for: place)
                            // Rare, GPS-gated: user saved a place while standing in it
                            CheckInViewController.offerIfAtPlace(place)

                            // No success popup — the piggy-bank coin drop IS
                            // the success feedback; an alert here covered it up
                            self?.navigateToCircleDetail()
                        case .failure(let error):
                            Logger.debug("❌ Failed to create place from POI: \(error)")
                            self?.endSaving()
                            self?.presentPlaceCreationError(error)
                        }
                    }
                }
            }
        } else {
            // No Google details or POI data, create place normally
            Logger.debug("📸 Creating non-Google place with pre-uploaded photos: \(self.uploadedPhotoUrls)")
            
            // Determine location to use - prioritize selectedLocation, then try geocoding
            var locationToUse = self.selectedLocation
            
            if locationToUse == nil {
                Logger.debug("🗺️ No location selected, attempting to geocode address: \(address)")
                
                PlaceService.shared.geocodeAddress(address) { [weak self] geocodeResult in
                    DispatchQueue.main.async {
                        switch geocodeResult {
                        case .success(let coordinate):
                            Logger.debug("✅ Successfully geocoded address to: \(coordinate)")
                            locationToUse = coordinate
                        case .failure(let error):
                            Logger.debug("⚠️ Geocoding failed: \(error.localizedDescription)")
                            // For place creation, location should be mandatory
                            loadingAlert.dismiss(animated: true) {
                                self?.endSaving()
                                self?.presentAlert(title: "Location Required",
                                                 message: "Could not determine location for this address. Please select a location on the map or try a different address.")
                            }
                            return
                        }
                        
                        // Now create the place with the geocoded location
                        self?.createPlaceWithLocation(
                            name: name,
                            description: description,
                            address: address,
                            category: category,
                            customCategory: customCategory,
                            subcategory: subcategory,
                            privacy: privacy,
                            photoData: photoData,
                            location: locationToUse!,
                            loadingAlert: loadingAlert,
                            force: force
                        )
                    }
                }
            } else {
                // Location already selected, create place directly
                self.createPlaceWithLocation(
                    name: name,
                    description: description,
                    address: address,
                    category: category,
                    customCategory: customCategory,
                    subcategory: subcategory,
                    privacy: privacy,
                    photoData: photoData,
                    location: locationToUse!,
                    loadingAlert: loadingAlert,
                    force: force
                )
            }
        }
    }
    
    func createPlaceWithLocation(name: String, description: String, address: String, 
                                       category: PlaceCategory, customCategory: String?, 
                                       subcategory: String?, privacy: PlacePrivacy,
                                       photoData: [Data]?, location: CLLocationCoordinate2D,
                                       loadingAlert: UIAlertController, force: Bool = false) {
        // Get notes from text views
        let privateNotes = privateNotesTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Location is now mandatory - ensure it's valid
        guard location.latitude >= -90 && location.latitude <= 90 &&
              location.longitude >= -180 && location.longitude <= 180 &&
              !(location.longitude == -180 && location.latitude == -180) else {
            loadingAlert.dismiss(animated: true) {
                self.presentAlert(title: "Invalid Location", 
                                message: "The location coordinates are invalid. Please select a valid location on the map.")
            }
            return
        }
        
        Logger.debug("📍 Creating place with location: \(location.latitude), \(location.longitude)")
        
        PlaceService.shared.createPlace(
            name: name,
            description: description.isEmpty ? nil : description,
            address: address,
            category: category,
            customCategory: customCategory,
            subcategory: subcategory,
            circleId: selectedCircleId,
            privacy: privacy,
            website: nil,
            phone: nil,
            tags: nil,
            photos: photoData,
            photoUrls: self.uploadedPhotoUrls.isEmpty ? nil : self.uploadedPhotoUrls,
            location: location,
            googlePlaceId: nil,
            privateNotes: privateNotes.isEmpty ? nil : privateNotes,
            neighborhood: selectedNeighborhood,
            applePoiCategory: selectedApplePoiCategory,
            userRating: userRating,
            force: force
        ) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let place):
                        Logger.debug("✅ Place created successfully")
                        Logger.debug("📸 DEBUG: Place returned with \(place.photos?.count ?? 0) photos:")
                        if let photos = place.photos {
                            for (index, photoUrl) in photos.enumerated() {
                                Logger.debug("  Photo \(index + 1): \(photoUrl)")
                            }
                        }
                        Logger.debug("📸 DEBUG: Originally uploaded \(self?.uploadedPhotoUrls.count ?? 0) photos:")
                        if let uploadedUrls = self?.uploadedPhotoUrls {
                            for (index, url) in uploadedUrls.enumerated() {
                                Logger.debug("  Uploaded \(index + 1): \(url)")
                            }
                        }
                        // Post notification that a place was added
                        NotificationCenter.default.post(
                            name: Notification.Name("PlaceAddedToCircle"),
                            object: nil,
                            userInfo: ["circleId": self?.selectedCircleId ?? "", "place": place]
                        )

                        self?.postPendingReviewIfNeeded(for: place)
                        // Rare, GPS-gated: user saved a place while standing in it
                        CheckInViewController.offerIfAtPlace(place)

                        // No success popup — the piggy-bank coin drop IS the
                        // success feedback; an alert here covered it up
                        self?.navigateToCircleDetail()
                    case .failure(let error):
                        Logger.debug("❌ Failed to create place: \(error)")
                        self?.endSaving()
                        self?.presentPlaceCreationError(error)
                    }
                }
            }
        }
    }

    func createPlaceWithGoogleDetails(googleDetails: GooglePlaceDetails,
                                            name: String,
                                            address: String,
                                            location: GeoLocation,
                                            category: PlaceCategory,
                                            description: String,
                                            privateNotes: String?,
                                            loadingAlert: UIAlertController,
                                            force: Bool = false) {
        Logger.debug("📸 Using pre-uploaded photos: \(self.uploadedPhotoUrls)")
        
        // Debug: Log rating information
        Logger.debug("📊 Creating place with rating info:")
        Logger.debug("  Rating: \(googleDetails.rating ?? 0)")
        Logger.debug("  Total Ratings: \(googleDetails.userRatingsTotal ?? 0)")
        
        PlaceService.shared.addPlaceFromPOI(
            name: name,
            address: address,
            location: location,
            category: category,
            website: googleDetails.website?.absoluteString,
            phone: googleDetails.phoneNumber,
            description: description.isEmpty ? nil : description,
            circleId: selectedCircleId,
            notes: privateNotes,
            googlePlaceId: googleDetails.placeID.isEmpty ? nil : googleDetails.placeID,
            preUploadedPhotoUrls: self.uploadedPhotoUrls.isEmpty ? nil : self.uploadedPhotoUrls,
            rating: googleDetails.rating,
            userRatingsTotal: googleDetails.userRatingsTotal,
            userRating: userRating,
            force: force
        ) { [weak self] result in
            DispatchQueue.main.async {
                loadingAlert.dismiss(animated: true) {
                    switch result {
                    case .success(let place):
                        Logger.debug("✅ Place created successfully (Google place with details)")
                        Logger.debug("  ID: \(place.id)")
                        Logger.debug("📸 DEBUG: Place returned with \(place.photos?.count ?? 0) photos:")
                        if let photos = place.photos {
                            for (index, photo) in photos.enumerated() {
                                Logger.debug("  Photo \(index + 1): \(photo)")
                            }
                        }
                        Logger.debug("📸 DEBUG: Originally uploaded \(self?.uploadedPhotoUrls.count ?? 0) photos:")
                        if let uploadedUrls = self?.uploadedPhotoUrls {
                            for (index, url) in uploadedUrls.enumerated() {
                                Logger.debug("  Uploaded \(index + 1): \(url)")
                            }
                        }
                        
                        // Post notification that a place was added
                        NotificationCenter.default.post(
                            name: Notification.Name("PlaceAddedToCircle"),
                            object: nil,
                            userInfo: ["circleId": self?.selectedCircleId ?? "", "place": place]
                        )

                        self?.postPendingReviewIfNeeded(for: place)
                        // Rare, GPS-gated: user saved a place while standing in it
                        CheckInViewController.offerIfAtPlace(place)

                        // No success popup — the piggy-bank coin drop IS the
                        // success feedback; an alert here covered it up
                        self?.navigateToCircleDetail()
                    case .failure(let error):
                        Logger.debug("❌ Failed to create place: \(error)")
                        self?.endSaving()
                        self?.presentPlaceCreationError(error)
                    }
                }
            }
        }
    }
}
