import Foundation

/// What the loader needs from the circle screen when places arrive. Each
/// method is the exact block of UI work the inline fetch used to do at that
/// point, in the same order.
protocol CirclePlacesLoaderDelegate: AnyObject {
    /// Success: store the places (already ordered by the backend), rebuild
    /// tag chips, apply the filter, refresh the add-place button title.
    func loaderDidLoadPlaces(_ places: [Place])
    /// Failure: show the empty state (no sample places), rebuild chips,
    /// refresh the add-place button title.
    func loaderDidFailToLoadPlaces(_ error: Error)
    /// Either way: reload the table, end refreshing, re-measure the table
    /// height on the next turn, redraw the map annotations.
    func loaderDidFinishLoadingPlaces()
}

/// Fetches a circle's places through the public endpoint for public
/// circles opened from a share link, and the authenticated endpoint
/// otherwise (Phase 5, circle-detail step 3).
final class CirclePlacesLoader {
    weak var delegate: CirclePlacesLoaderDelegate?

    // Service seams (tests inject fakes)
    var fetchPublic: (_ circleId: String, _ completion: @escaping (Result<[Place], Error>) -> Void) -> Void = { circleId, completion in
        PlaceService.shared.fetchPlacesByCircleIdPublic(circleId: circleId, completion: completion)
    }
    var fetchAuthenticated: (_ circleId: String, _ completion: @escaping (Result<[Place], Error>) -> Void) -> Void = { circleId, completion in
        PlaceService.shared.fetchPlacesByCircleId(circleId: circleId, completion: completion)
    }

    /// Public circles reached through a share link may be viewed without an
    /// account, so they load through the public endpoint.
    static func usesPublicEndpoint(privacy: PrivacyLevel, isSharedViaLink: Bool) -> Bool {
        privacy == .public && isSharedViaLink
    }

    func fetchPlaces(for circle: Circle, isSharedViaLink: Bool) {
        Logger.debug("🔍 CircleDetailViewController: About to fetch places for circle: \(circle.name) (ID: \(circle.id))")
        Logger.debug("   - Circle privacy: \(circle.privacy)")
        Logger.debug("   - Is shared via link: \(isSharedViaLink)")

        let usesPublic = CirclePlacesLoader.usesPublicEndpoint(privacy: circle.privacy, isSharedViaLink: isSharedViaLink)
        let fetch = usesPublic ? fetchPublic : fetchAuthenticated
        let label = usesPublic ? "public circle" : "circle"
        fetch(circle.id) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let places):
                    Logger.info("Fetched \(places.count) places for \(label): \(circle.name)")
                    // Places are already ordered by the backend based on the circle's places array
                    self?.delegate?.loaderDidLoadPlaces(places)
                case .failure(let error):
                    Logger.error("Failed to fetch places\(usesPublic ? " for public circle" : ""): \(error.localizedDescription)")
                    // Don't use sample places - show empty state instead
                    self?.delegate?.loaderDidFailToLoadPlaces(error)
                }
                self?.delegate?.loaderDidFinishLoadingPlaces()
            }
        }
    }
}
