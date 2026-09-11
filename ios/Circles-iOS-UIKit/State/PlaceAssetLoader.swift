import UIKit
import CoreLocation

/// What the asset pipeline needs from the add-place form. The photo state
/// stays on the controller (the save flow, the photo picker and the
/// manual-location tap all read and reset it); the loader reads and writes
/// it through these accessors at exactly the points the inline code did.
protocol PlaceAssetLoaderDelegate: AnyObject {
    var selectedGooglePlaceDetails: GooglePlaceDetails? { get set }
    var uploadedPhotoUrls: [String] { get set }
    var downloadedGoogleImage: UIImage? { get set }
    var downloadedLookAroundImage: UIImage? { get set }
    var photosWereAutoPopulated: Bool { get set }
    var selectedImage: UIImage? { get set }

    /// Reset pipeline-sourced photo state before a new selection loads.
    func clearAutoPopulatedPhotoState()
    /// Put a pipeline photo in the photo box (image view + button toggles).
    func showPipelinePhoto(_ image: UIImage)
    /// Swap the synthesized description for real editorial text.
    func upgradeDescriptionWithEditorialSummary(_ summary: String?)
}

/// Fetches a venue's photos and Google details for the add-place form:
/// canonical match in our own database first (no Google spend), then
/// Google Places Find → Details → photo download/upload, plus an Apple
/// Look Around snapshot. Owns the request token that makes stale responses
/// from a previous selection harmless (Phase 5 step 5 of the plan).
///
/// Main-actor isolated like the controller it came from: the completion
/// closures and the Look Around task inherit that isolation exactly as
/// they did inline.
@MainActor
final class PlaceAssetLoader {
    weak var delegate: PlaceAssetLoaderDelegate?

    /// Rotated on every new map/POI/search selection. Async place-asset work
    /// (canonical match, Google details, photo download/upload) captures the
    /// token when it starts and re-checks it before touching form state —
    /// stale responses from a previous tap were attaching the wrong venue's
    /// photo and details (Ilios name + Magnetic Pole Fit photo, 2026-08-22).
    var requestToken = UUID()

    // MARK: Service seams (tests inject fakes)

    var matchKnownPlace: (_ name: String, _ latitude: Double, _ longitude: Double, _ address: String?,
                          _ completion: @escaping (Result<KnownPlaceMatch?, Error>) -> Void) -> Void = { name, latitude, longitude, address, completion in
        GlobalPlaceService.shared.matchKnownPlace(name: name, latitude: latitude, longitude: longitude, address: address, completion: completion)
    }

    var loadImage: (_ url: String, _ completion: @escaping (UIImage?) -> Void) -> Void = { url, completion in
        ImageService.shared.loadImage(from: url, completion: completion)
    }

    /// A captured token is still the live one. `nil` = the caller predates
    /// token tracking (user-picked photos) and is never stale.
    static func isCurrent(token: UUID?, live: UUID) -> Bool {
        token == nil || token == live
    }

    // MARK: Pipeline

    func fetchPlaceAssets(name: String, coordinate: CLLocationCoordinate2D, address: String?) {
        // New selection: everything still in flight for the previous one is stale
        let token = UUID()
        requestToken = token
        delegate?.clearAutoPopulatedPhotoState()
        matchKnownPlace(name, coordinate.latitude, coordinate.longitude, address) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, let delegate = self.delegate else { return }
                guard self.requestToken == token else { return }

                if case .success(let match?) = result, let googlePlaceId = match.googlePlaceId, !googlePlaceId.isEmpty {
                    Logger.debug("✅ Venue already in our database (\(match.globalPlaceId)) — skipping Google Places")
                    delegate.selectedGooglePlaceDetails = GooglePlaceDetails(
                        placeID: googlePlaceId,
                        name: match.name,
                        address: match.address ?? address,
                        coordinate: coordinate
                    )
                    // Canonical photos are Firebase URLs — reuse directly,
                    // no download/re-upload needed
                    if delegate.uploadedPhotoUrls.isEmpty && !match.photos.isEmpty {
                        delegate.uploadedPhotoUrls = Array(match.photos.prefix(5))
                        delegate.photosWereAutoPopulated = true
                        Logger.debug("📸 Reusing \(delegate.uploadedPhotoUrls.count) canonical photos")
                        // Show it too — URLs alone left the photo box stuck
                        // on whatever the previous selection displayed
                        if let firstUrl = delegate.uploadedPhotoUrls.first {
                            self.loadImage(firstUrl) { [weak self] image in
                                DispatchQueue.main.async {
                                    guard let self = self, let delegate = self.delegate,
                                          self.requestToken == token,
                                          let image = image else { return }
                                    delegate.selectedImage = image
                                    delegate.showPipelinePhoto(image)
                                }
                            }
                        }
                    }
                    // Reuse the canonical description too — beats the
                    // synthesized "Category in City" placeholder
                    delegate.upgradeDescriptionWithEditorialSummary(match.description)
                    return
                }

                self.searchGoogleForPlaceAssets(name: name, coordinate: coordinate, address: address, token: token)
            }
        }
    }

    /// The Google Places pipeline (Find Place → Details → photo upload),
    /// used only when the venue is new to our database.
    func searchGoogleForPlaceAssets(name: String, coordinate: CLLocationCoordinate2D, address: String?, token: UUID) {
        Logger.debug("🔍 Searching Google Places for: \(name)")
        GooglePlacesService.shared.searchPlaceByNameAndLocation(
            name: name,
            coordinate: coordinate,
            address: address ?? ""
        ) { [weak self] result in
            switch result {
            case .success(let prediction):
                if let prediction = prediction {
                    Logger.debug("✅ Found Google Place match: \(prediction.attributedPrimaryText.string)")
                    GooglePlacesService.shared.fetchPlaceDetails(placeID: prediction.placeID) { detailsResult in
                        switch detailsResult {
                        case .success(let place):
                            let googleDetails = GooglePlaceDetails(from: place)
                            DispatchQueue.main.async {
                                guard self?.requestToken == token else { return }
                                self?.delegate?.selectedGooglePlaceDetails = googleDetails
                                // Swap the generic synthesized description for
                                // Google's real one, if this venue has one
                                self?.delegate?.upgradeDescriptionWithEditorialSummary(googleDetails.editorialSummary)
                                // Only preload photos if we haven't already uploaded any
                                if self?.delegate?.uploadedPhotoUrls.isEmpty == true {
                                    self?.preloadAndUploadPhotosForPlace(googleDetails, token: token)
                                } else {
                                    Logger.debug("📸 Skipping photo preload - already have \(self?.delegate?.uploadedPhotoUrls.count ?? 0) uploaded photos")
                                }
                            }
                        case .failure(let error):
                            Logger.debug("❌ Failed to fetch Google Place details: \(error)")
                        }
                    }
                } else {
                    Logger.debug("⚠️ No Google Place match found for: \(name)")
                }
            case .failure(let error):
                Logger.debug("❌ Failed to search Google Places: \(error)")
            }
        }
    }

    func preloadAndUploadPhotosForPlace(_ placeDetails: GooglePlaceDetails, token: UUID? = nil) {
        guard let delegate = delegate else { return }
        // nil token = caller predates token tracking (user-picked photos);
        // otherwise every async completion below re-checks currency
        func assetsStillCurrent() -> Bool { PlaceAssetLoader.isCurrent(token: token, live: requestToken) }
        Logger.debug("🚀 Pre-loading photos for place: \(placeDetails.name)")
        Logger.debug("📸 DEBUG: Starting photo pre-load process")
        Logger.debug("📸 DEBUG: Existing uploaded URLs count: \(delegate.uploadedPhotoUrls.count)")
        Logger.debug("📸 DEBUG: Already have Google image: \(delegate.downloadedGoogleImage != nil)")

        // Don't reset if we already have photos - this prevents duplicate uploads
        if delegate.uploadedPhotoUrls.isEmpty {
            // Only reset if we don't have any uploaded photos yet
            delegate.downloadedGoogleImage = nil
            delegate.downloadedLookAroundImage = nil
            Logger.debug("📸 DEBUG: No existing uploads, cleared downloaded images")
        } else {
            Logger.debug("📸 DEBUG: Keeping existing \(delegate.uploadedPhotoUrls.count) uploaded photo URLs")
            for (index, url) in delegate.uploadedPhotoUrls.enumerated() {
                Logger.debug("  Existing photo \(index + 1): \(url)")
            }
        }

        let photoGroup = DispatchGroup()

        // Handle Google Place photo
        if !placeDetails.photos.isEmpty {
            if let existingImage = delegate.downloadedGoogleImage {
                // We already have a downloaded image, just upload it
                Logger.debug("📸 Using existing downloaded Google photo")
                if delegate.uploadedPhotoUrls.isEmpty {
                    photoGroup.enter()
                    if let imageData = existingImage.jpegData(compressionQuality: 0.8) {
                        Logger.debug("📸 Uploading Google photo (size: \(imageData.count / 1024) KB)...")
                        self.uploadImageData(imageData) { uploadedUrl in
                            if let url = uploadedUrl, assetsStillCurrent() {
                                if !delegate.uploadedPhotoUrls.contains(url) {
                                    delegate.photosWereAutoPopulated = true
                                    delegate.uploadedPhotoUrls.append(url)
                                    Logger.debug("✅ Google photo uploaded: \(url)")
                                } else {
                                    Logger.debug("⚠️ Skipping duplicate photo URL: \(url)")
                                }
                            }
                            photoGroup.leave()
                        }
                    } else {
                        photoGroup.leave()
                    }
                } else {
                    Logger.debug("📸 Skipping Google photo upload - already have \(delegate.uploadedPhotoUrls.count) uploaded photos")
                }
            } else {
                // Need to download and upload the photo
                photoGroup.enter()
                Logger.debug("📸 Loading photo from Google Places...")
                GooglePlacesService.shared.loadPhoto(from: placeDetails.photos[0], maxSize: CGSize(width: 800, height: 800)) { [weak self] result in
                    switch result {
                    case .success(let image):
                        Logger.debug("📸 Successfully loaded Google photo")
                        self?.delegate?.downloadedGoogleImage = image

                        // Show in UI immediately — unless the user has
                        // since selected a different place
                        DispatchQueue.main.async {
                            guard assetsStillCurrent() else { return }
                            self?.delegate?.photosWereAutoPopulated = true
                            self?.delegate?.selectedImage = image
                            self?.delegate?.showPipelinePhoto(image)
                        }

                        // Only upload if we don't already have uploaded photos
                        if self?.delegate?.uploadedPhotoUrls.isEmpty == true {
                            if let imageData = image.jpegData(compressionQuality: 0.8) {
                                Logger.debug("📸 Uploading Google photo (size: \(imageData.count / 1024) KB)...")
                                self?.uploadImageData(imageData) { uploadedUrl in
                                    if let url = uploadedUrl, assetsStillCurrent() {
                                        // Check for duplicates before appending
                                        if !(self?.delegate?.uploadedPhotoUrls.contains(url) ?? false) {
                                            self?.delegate?.photosWereAutoPopulated = true
                                            self?.delegate?.uploadedPhotoUrls.append(url)
                                            Logger.debug("✅ Google photo uploaded: \(url)")
                                        } else {
                                            Logger.debug("⚠️ Skipping duplicate photo URL: \(url)")
                                        }
                                    }
                                    photoGroup.leave()
                                }
                            } else {
                                photoGroup.leave()
                            }
                        } else {
                            Logger.debug("📸 Skipping Google photo upload - already have \(self?.delegate?.uploadedPhotoUrls.count ?? 0) uploaded photos")
                            photoGroup.leave()
                        }

                    case .failure(let error):
                        Logger.debug("❌ Failed to load Google photo: \(error)")
                        photoGroup.leave()
                    }
                }
            }
        }

        // Try Apple Look Around
        if #available(iOS 16.0, *) {
            photoGroup.enter()
            Task {
                Logger.debug("📸 Checking Apple Look Around...")
                let hasLookAround = await AppleLookAroundService.shared.checkLookAroundAvailability(at: placeDetails.coordinate)

                if hasLookAround {
                    Logger.debug("✅ Look Around is available")
                    do {
                        let lookAroundImage = try await AppleLookAroundService.shared.getLookAroundSnapshot(at: placeDetails.coordinate)
                        delegate.downloadedLookAroundImage = lookAroundImage

                        // If no Google photo, show Look Around in UI
                        if delegate.downloadedGoogleImage == nil {
                            DispatchQueue.main.async {
                                guard assetsStillCurrent() else { return }
                                delegate.photosWereAutoPopulated = true
                                delegate.selectedImage = lookAroundImage
                                delegate.showPipelinePhoto(lookAroundImage)
                            }
                        }

                        // Upload the image
                        if let imageData = lookAroundImage.jpegData(compressionQuality: 0.8) {
                            Logger.debug("📸 Uploading Look Around photo (size: \(imageData.count / 1024) KB)...")
                            self.uploadImageData(imageData) { uploadedUrl in
                                if let url = uploadedUrl, assetsStillCurrent() {
                                    // Check for duplicates before appending
                                    if !delegate.uploadedPhotoUrls.contains(url) {
                                        delegate.photosWereAutoPopulated = true
                                        delegate.uploadedPhotoUrls.append(url)
                                        Logger.debug("✅ Look Around photo uploaded: \(url)")
                                    } else {
                                        Logger.debug("⚠️ Skipping duplicate photo URL: \(url)")
                                    }
                                }
                                photoGroup.leave()
                            }
                        } else {
                            photoGroup.leave()
                        }
                    } catch {
                        Logger.debug("❌ Failed to get Look Around snapshot: \(error)")
                        photoGroup.leave()
                    }
                } else {
                    Logger.debug("⚠️ Look Around not available")
                    photoGroup.leave()
                }
            }
        }

        // Log completion
        photoGroup.notify(queue: .main) {
            Logger.debug("📸 DEBUG: Photo pre-loading complete")
            Logger.debug("📸 DEBUG: Total photos uploaded: \(delegate.uploadedPhotoUrls.count)")
            Logger.debug("📸 DEBUG: Google image downloaded: \(delegate.downloadedGoogleImage != nil)")
            Logger.debug("📸 DEBUG: Look Around image downloaded: \(delegate.downloadedLookAroundImage != nil)")
            for (index, url) in delegate.uploadedPhotoUrls.enumerated() {
                Logger.debug("  Uploaded photo \(index + 1): \(url)")
            }
        }
    }

    func uploadImageData(_ imageData: Data, completion: @escaping (String?) -> Void) {
        PlaceService.shared.uploadMultipleImages([imageData]) { result in
            switch result {
            case .success(let urls):
                completion(urls.first)
            case .failure(let error):
                Logger.debug("❌ Image upload failed: \(error)")
                completion(nil)
            }
        }
    }
}
