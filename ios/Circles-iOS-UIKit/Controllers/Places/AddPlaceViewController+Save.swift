import UIKit
import CoreLocation

// The save flow for AddPlaceViewController: Save tap → validation →
// place creation (the server answers duplicates) → staged alerts (three payload builders,
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
        
        // Guard the whole create flow (create -> navigate) against a second
        // tap; released on every failure/cancel path
        beginSaving()

        // Straight to the save. The server answers "you already have this
        // in <circle>" itself (DUPLICATE_PLACE, handled in
        // handleCreationFailure) — this used to download every place in
        // every circle first, which hung on a weak signal (Wes, 2026-10-04).
        let attempt: (Bool) -> Void = { [weak self] force in
            self?.proceedWithPlaceCreation(
                name: name,
                address: address,
                description: description,
                category: category,
                customCategory: customCategory,
                subcategory: subcategory,
                privacy: privacy,
                privateNotes: privateNotes.isEmpty ? nil : privateNotes,
                force: force
            )
        }
        addAnywayRetry = { [weak self] in
            self?.beginSaving()
            attempt(true)
        }
        attempt(false)
    }

    // MARK: - "You already have this place"

    /// Re-runs the last save with the duplicate check off ("Add Anyway").
    /// Held on the controller (an extension can't add stored properties).
    var addAnywayRetry: (() -> Void)? {
        get { objc_getAssociatedObject(self, &AddPlaceSaveKeys.retry) as? () -> Void }
        set { objc_setAssociatedObject(self, &AddPlaceSaveKeys.retry, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }

    /// Every failed save lands here: a duplicate gets its choices, anything
    /// else the usual error (incl. the place-limit paywall).
    func handleCreationFailure(_ error: Error) {
        guard let duplicate = PlaceDuplicate.from(error) else {
            presentPlaceCreationError(error)
            return
        }
        let alert = UIAlertController(title: "Similar Place Found", message: duplicate.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "View Place", style: .default) { [weak self] _ in
            self?.showExistingPlace(duplicate.placeId)
        })
        alert.addAction(UIAlertAction(title: "Add Anyway", style: .default) { [weak self] _ in
            self?.addAnywayRetry?()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    /// Leave Add Place and open the place they already saved.
    private func showExistingPlace(_ placeId: String) {
        let open = {
            NotificationCenter.default.post(name: Notification.Name("NavigateToPlace"), object: placeId)
        }
        if presentingViewController != nil {
            dismiss(animated: true, completion: open)
        } else {
            navigationController?.popViewController(animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: open)
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
                force: force,
                offersPostSaveNudges: true
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
                            // The post-save offer (check in here / send a
                            // postcard) is arranged by PlaceService, which
                            // knows what the coin drop and milestone are doing
                            ProximityNotificationScheduler.shared.replanFromCache(force: true)

                            // No success popup — the piggy-bank coin drop IS
                            // the success feedback; an alert here covered it up
                            self?.navigateToCircleDetail()
                        case .failure(let error):
                            Logger.debug("❌ Failed to create place from POI: \(error)")
                            self?.endSaving()
                            self?.handleCreationFailure(error)
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
            force: force,
            offersPostSaveNudges: true
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
                        // The post-save offer (check in here / send a postcard)
                        // is arranged by PlaceService, which knows what the
                        // coin drop and milestone are doing
                        ProximityNotificationScheduler.shared.replanFromCache(force: true)

                        // No success popup — the piggy-bank coin drop IS the
                        // success feedback; an alert here covered it up
                        self?.navigateToCircleDetail()
                    case .failure(let error):
                        Logger.debug("❌ Failed to create place: \(error)")
                        self?.endSaving()
                        self?.handleCreationFailure(error)
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
            force: force,
            offersPostSaveNudges: true
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
                        // The post-save offer (check in here / send a postcard)
                        // is arranged by PlaceService, which knows what the
                        // coin drop and milestone are doing
                        ProximityNotificationScheduler.shared.replanFromCache(force: true)

                        // No success popup — the piggy-bank coin drop IS the
                        // success feedback; an alert here covered it up
                        self?.navigateToCircleDetail()
                    case .failure(let error):
                        Logger.debug("❌ Failed to create place: \(error)")
                        self?.endSaving()
                        self?.handleCreationFailure(error)
                    }
                }
            }
        }
    }
}

private enum AddPlaceSaveKeys {
    static var retry: UInt8 = 0
}
