import UIKit
import MapKit

// Create/Edit circle and full-screen-map delegate conformances for
// CirclesHomeViewController. Extracted from the main controller (Wave 4).

// MARK: - CreateCircleDelegate
extension CirclesHomeViewController: CreateCircleDelegate {
    func didCreateCircle(_ circle: Circle) {
        Logger.debug("✅ Circle created successfully: \(circle.name)")
        
        // Add the new circle to our local array at the beginning
        circles.insert(circle, at: 0)
        updateEmptyState()
        updateMapPlaces()
        
        // Dismiss the modal CreateCircleViewController first
        dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            // After dismissal, navigate to AddPlaceViewController with the new circle
            let addPlaceVC = AddPlaceViewController(circleId: circle.id)
            self.navigationController?.pushViewController(addPlaceVC, animated: true)
        }
    }
}

// MARK: - EditCircleDelegate
extension CirclesHomeViewController: EditCircleDelegate {
    func didUpdateCircle(_ circle: Circle) {
        // Find and update the circle in the array
        if let index = circles.firstIndex(where: { $0.id == circle.id }) {
            circles[index] = circle
            updateMapPlaces()
        }
    }
    
    func didDeleteCircle(_ circleId: String) {
        // Find and remove the circle from the array
        if let index = circles.firstIndex(where: { $0.id == circleId }) {
            circles.remove(at: index)
            updateEmptyState()
            updateMapPlaces()
        }
    }
}

// MARK: - FullScreenMapViewControllerDelegate
extension CirclesHomeViewController: FullScreenMapViewControllerDelegate {
    func mapViewController(_ controller: FullScreenMapViewController, regionDidChangeTo region: MKCoordinateRegion) {
        guard useViewportNetworkLoading else { return }

        // While filtered to a specific connection, their places are already
        // fully loaded and everyone else's are filtered out — a viewport fetch
        // would just cause pointless network traffic and pin churn after zooms
        if let connectionId = selectedConnectionId, connectionId != "my_places_only" {
            return
        }

        fetchViewportPlaces(region: region, for: controller)
    }

    func mapViewController(_ controller: FullScreenMapViewController, didChangeConnectionFilter connectionId: String?) {
        // Fires from BOTH maps now: the modal mirrors back on dismissal, and
        // the embedded map's Connection dropdown drives this controller
        // directly — that's what keeps the map and the rest of the home page
        // on one shared connection scope. Loop-safe: the reply channel
        // (setConnectionSelection) updates the label without re-firing this.

        let user: User? = {
            guard let id = connectionId, id != "my_places_only" else { return nil }
            let currentUserId = AuthService.shared.getUserId() ?? ""
            return NetworkManager.shared.connections.first(where: {
                IDNormalizer.isSameUser($0.otherUserId(currentUserId: currentUserId), id)
            })?.connectedUser
        }()

        Logger.debug("🗺️ Mirroring full-screen map connection filter: \(connectionId ?? "All Connections")")
        selectConnection(id: connectionId, user: user)
    }

    func mapViewControllerDidChangeChipFilters(_ controller: FullScreenMapViewController) {
        // Only the EMBEDDED map's chips drive the home list — the modal's chips
        // are its own view state and shouldn't reshuffle the page behind it.
        guard controller === mapViewController else { return }
        if isShowingPlacesList {
            rebuildDistanceSortedPlaces()
            placesListTableView.reloadData()
        }
    }

    func mapViewController(_ controller: FullScreenMapViewController, didSelectPlace place: Place) {
        let timestamp = Date().timeIntervalSince1970
        Logger.debug("🎯 [DEBUG-\(timestamp)] CirclesHomeViewController.mapViewController called for place: \(place.name)")
        Logger.debug("🗺️ [DEBUG-\(timestamp)] Controller isPresentedModally: \(controller.isPresentedModally)")
        
        // Deduplication check to prevent double presentation
        let timeSinceLastPresentation = timestamp - lastPresentationTime
        if lastPresentedPlaceId == place.id && timeSinceLastPresentation < presentationDebounceInterval {
            Logger.debug("🚫 [DEBUG-\(timestamp)] Duplicate presentation blocked - same place (\(place.name)) presented \(timeSinceLastPresentation) seconds ago")
            return
        }
        
        // Update deduplication tracking
        lastPresentedPlaceId = place.id
        lastPresentationTime = timestamp
        
        guard let circle = resolveCircle(for: place) else {
            Logger.debug("⚠️ [DEBUG-\(timestamp)] Place not found in any circle (circleId: \(place.circleId ?? "nil"))")
            return
        }

        Logger.debug("✅ [DEBUG-\(timestamp)] Found place in circle: \(circle.name)")
        let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
        Logger.debug("📱 [DEBUG-\(timestamp)] Created PlaceDetailViewController - presenting...")
        presentPlaceDetail(placeDetailVC, from: controller)
    }
    
    func presentPlaceDetail(_ placeDetailVC: PlaceDetailViewController, from controller: FullScreenMapViewController) {
        let timestamp = Date().timeIntervalSince1970
        Logger.debug("🎭 [DEBUG-\(timestamp)] presentPlaceDetail called")
        Logger.debug("🗺️ [DEBUG-\(timestamp)] Controller isPresentedModally: \(controller.isPresentedModally)")
        
        // Check if the map controller is presented modally
        if controller.isPresentedModally {
            Logger.debug("📄 [DEBUG-\(timestamp)] Presenting PlaceDetail modally on full-screen map")
            // Present place detail modally on top of the full screen map
            let navController = UINavigationController(rootViewController: placeDetailVC)
            navController.modalPresentationStyle = .pageSheet
            controller.present(navController, animated: true)
        } else {
            Logger.debug("📱 [DEBUG-\(timestamp)] Pushing PlaceDetail via navigation for embedded map")
            // For embedded map, use regular navigation push
            navigationController?.pushViewController(placeDetailVC, animated: true)
        }
        Logger.debug("🎭 [DEBUG-\(timestamp)] presentPlaceDetail completed")
    }
}

