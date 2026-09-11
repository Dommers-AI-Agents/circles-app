import Foundation

/// What the place page does with each venue-side fetch. Every callback
/// arrives on the main queue.
protocol VenueRewardsLoaderDelegate: AnyObject {
    /// The place as it is NOW — the page can refresh its copy while a
    /// request is in flight, and partner eligibility is judged on the latest.
    func currentPlace(for loader: VenueRewardsLoader) -> Place
    func loader(_ loader: VenueRewardsLoader, didLoadPartnerActionGroups groups: [PartnerActionGroup])
    func loader(_ loader: VenueRewardsLoader, didLoadVenueData data: PlaceVenueData)
    /// Additive section — a failed lookup just leaves it collapsed.
    func loaderVenueLookupFailed(_ loader: VenueRewardsLoader)
    func loader(_ loader: VenueRewardsLoader, didLoadGlobalPlace globalPlace: GlobalPlace)
    /// The legacy Place model stays in use; a retry may still be pending.
    func loaderGlobalPlaceLookupFailed(_ loader: VenueRewardsLoader)
}

/// Fetches the place page's venue-side data: partner action chips, the
/// venue rewards / claim card, and the canonical GlobalPlace (photo
/// attribution, cover photo). Owns the one-retry rule for transient
/// GlobalPlace failures. The services are injectable for tests.
final class VenueRewardsLoader {
    weak var delegate: VenueRewardsLoaderDelegate?

    /// Wait before the single GlobalPlace retry.
    var retryDelay: TimeInterval = 2.0

    // MARK: Service seams (defaults hit the shared services)

    var fetchCatalog: (_ completion: @escaping (PartnerActionCatalog) -> Void) -> Void = { completion in
        PartnerActionsService.shared.getCatalog(completion: completion)
    }
    var fetchVenue: (_ placeId: String, _ googlePlaceId: String?, _ completion: @escaping (Result<PlaceVenueData, Error>) -> Void) -> Void = { placeId, googlePlaceId, completion in
        RewardsService.shared.getVenueByPlace(placeId: placeId, googlePlaceId: googlePlaceId, completion: completion)
    }
    var fetchGlobalPlace: (_ id: String, _ completion: @escaping (Result<GlobalPlaceResponse, Error>) -> Void) -> Void = { id, completion in
        GlobalPlaceService.shared.getGlobalPlace(id: id, completion: completion)
    }

    // MARK: - Partner actions

    func loadPartnerActions() {
        fetchCatalog { [weak self] catalog in
            DispatchQueue.main.async {
                guard let self = self, let delegate = self.delegate else { return }
                let place = delegate.currentPlace(for: self)
                let groups = PartnerActionsService.shared.eligibleGroups(for: place, from: catalog)
                delegate.loader(self, didLoadPartnerActionGroups: groups)
            }
        }
    }

    // MARK: - Venue rewards / claim card

    func loadVenueRewards() {
        guard let place = delegate?.currentPlace(for: self) else { return }
        fetchVenue(place.globalPlaceId ?? place.id, place.googlePlaceId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, let delegate = self.delegate else { return }
                switch result {
                case .success(let data):
                    delegate.loader(self, didLoadVenueData: data)
                case .failure:
                    delegate.loaderVenueLookupFailed(self)
                }
            }
        }
    }

    // MARK: - GlobalPlace (attribution, cover photo)

    func loadGlobalPlaceData() {
        // Try to load global place data if available
        // This provides better photo attribution and user tags
        guard let place = delegate?.currentPlace(for: self) else { return }
        Logger.debug("🔍 [PlaceDetailViewController] Starting loadGlobalPlaceData for place: \(place.name)")

        // Same id preference as the upload path (MediaStorageService), so reads
        // and writes resolve to the same GlobalPlace doc
        fetchGlobalPlace(place.globalPlaceId ?? place.id) { [weak self] result in
            switch result {
            case .success(let globalPlaceResponse):
                DispatchQueue.main.async {
                    guard let self = self, let delegate = self.delegate else { return }
                    Logger.debug("✅ [PlaceDetailViewController] GlobalPlace data loaded successfully")
                    Logger.debug("📍 [PlaceDetailViewController] GlobalPlace name: \(globalPlaceResponse.globalPlace.name)")
                    Logger.debug("🆔 [PlaceDetailViewController] GlobalPlace ID: \(globalPlaceResponse.globalPlace.id)")

                    let photoCount = globalPlaceResponse.globalPlace.photos?.count ?? 0
                    Logger.debug("📷 [PlaceDetailViewController] Loaded GlobalPlace with \(photoCount) attributed photos")

                    if let photos = globalPlaceResponse.globalPlace.photos, !photos.isEmpty {
                        let firstPhoto = photos[0]
                        Logger.debug("📸 [PlaceDetailViewController] First photo by: '\(firstPhoto.uploadedByName ?? "Unknown")'")
                    }

                    // Refresh media carousel with attribution data
                    Logger.debug("🔄 [PlaceDetailViewController] Calling updateMediaCarousel() with GlobalPlace data")
                    delegate.loader(self, didLoadGlobalPlace: globalPlaceResponse.globalPlace)
                }
            case .failure(let error):
                Logger.debug("❌ [PlaceDetailViewController] Could not load GlobalPlace data: \(error)")
                Logger.debug("📍 [PlaceDetailViewController] Continuing with legacy Place model for: \(place.name)")

                DispatchQueue.main.async {
                    guard let self = self else { return }
                    // Try to add retry logic for common failures
                    if Self.shouldRetryGlobalPlace(after: error) {
                        Logger.debug("🔄 [PlaceDetailViewController] Transient failure, will retry GlobalPlace lookup once")
                        // Retry once after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + self.retryDelay) { [weak self] in
                            self?.retryGlobalPlaceDataLoad()
                        }
                    }

                    // Continue with legacy Place model - no attribution data
                    // But update media carousel to ensure photos are shown
                    self.delegate?.loaderGlobalPlaceLookupFailed(self)
                }
            }
        }
    }

    /// No internet or a failed request gets one more try; anything else
    /// (not found, decoding) is final.
    static func shouldRetryGlobalPlace(after error: Error) -> Bool {
        if case APIError.noInternet = error { return true }
        if case APIError.requestFailed = error { return true }
        return false
    }

    private func retryGlobalPlaceDataLoad() {
        Logger.debug("🔄 [PlaceDetailViewController] Retrying GlobalPlace data load...")
        guard let place = delegate?.currentPlace(for: self) else { return }

        fetchGlobalPlace(place.globalPlaceId ?? place.id) { [weak self] result in
            switch result {
            case .success(let globalPlaceResponse):
                DispatchQueue.main.async {
                    guard let self = self, let delegate = self.delegate else { return }
                    Logger.debug("✅ [PlaceDetailViewController] GlobalPlace data loaded on retry")
                    delegate.loader(self, didLoadGlobalPlace: globalPlaceResponse.globalPlace)
                }
            case .failure(let error):
                Logger.debug("❌ [PlaceDetailViewController] GlobalPlace retry failed: \(error)")
                // Give up and continue with legacy data
            }
        }
    }
}
