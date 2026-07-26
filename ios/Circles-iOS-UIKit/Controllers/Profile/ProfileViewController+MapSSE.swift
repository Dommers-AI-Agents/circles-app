import UIKit
import MapKit
import CoreLocation
import PhotosUI

// SSE and map-view delegates for ProfileViewController. Extracted from the main controller (Wave 4).

// MARK: - SSEServiceDelegate
extension ProfileViewController: SSEServiceDelegate {
    func sseService(_ service: SSEService, didReceiveEvent event: SSEEvent) {
        guard let currentUserId = AuthService.shared.getUserId(),
              let userId = user?.id,
              userId == currentUserId else {
            // Only update stats for current user's profile
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch event.type {
            case .followerAdded, .followerRemoved:
                if let followersCount = event.data["followersCount"] as? Int {
                    self.followersStatView.configure(number: "\(followersCount)", title: "Followers")
                }
            case .followingAdded, .followingRemoved:
                Logger.debug("🔔 SSE Event: \(event.type) - Data: \(event.data)")
                let followingCount = event.data["followingCount"] as? Int
                if let followingCount = followingCount {
                    self.followingStatView.configure(number: "\(followingCount)", title: "Following")
                }
                // Update the cached current user's following array
                if let following = event.data["following"] as? [String],
                   var currentUser = AuthService.shared.currentUser {
                    // Create updated user with new following array
                    let updatedUser = currentUser.copy(
                        following: following,
                        followingCount: followingCount ?? currentUser.followingCount
                    )
                    AuthService.shared.updateCurrentUser(updatedUser)
                    
                    // Only re-check follow status if we're viewing someone else's profile
                    // (not when we just clicked follow/unfollow)
                    if self.user?.id != currentUserId {
                        self.checkConnectionAndFollowStatus()
                    }
                }
            default:
                break
            }
        }
    }
    
    func sseServiceDidConnect(_ service: SSEService) {
        // Connection established
    }
    
    func sseServiceDidDisconnect(_ service: SSEService, error: Error?) {
        // Connection lost
    }
}

// MARK: - MKMapViewDelegate
extension ProfileViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Skip user location
        if annotation is MKUserLocation {
            return nil
        }
        
        guard let placeAnnotation = annotation as? PlaceAnnotation else {
            return nil
        }
        
        let identifier = "PlaceAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
            
            // Add detail button
            let detailButton = UIButton(type: .detailDisclosure)
            annotationView?.rightCalloutAccessoryView = detailButton
        } else {
            annotationView?.annotation = annotation
        }
        
        // Customize marker appearance based on category
        if let markerView = annotationView {
            markerView.markerTintColor = placeAnnotation.place.category.color
            markerView.glyphImage = UIImage(systemName: placeAnnotation.place.category.systemIconName)
        }
        
        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let placeAnnotation = view.annotation as? PlaceAnnotation else { return }
        
        // Navigate to place detail view
        let placeDetailVC = PlaceDetailViewController(place: placeAnnotation.place)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
    
}

// MARK: - Search Scope
extension ProfileViewController {
    func updateSearchScopeMenu() {
        let iconName = profileSearchScope == .places ? "mappin.circle" : "circle.grid.2x2"
        searchScopeButton.setImage(UIImage(systemName: iconName), for: .normal)
        searchScopeButton.menu = UIMenu(children: [
            UIAction(
                title: "Places",
                image: UIImage(systemName: "mappin.circle"),
                state: profileSearchScope == .places ? .on : .off
            ) { [weak self] _ in self?.setSearchScope(.places) },
            UIAction(
                title: "Circles",
                image: UIImage(systemName: "circle.grid.2x2"),
                state: profileSearchScope == .circles ? .on : .off
            ) { [weak self] _ in self?.setSearchScope(.circles) }
        ])
    }

    func setSearchScope(_ scope: ProfileSearchScope) {
        guard scope != profileSearchScope else { return }
        profileSearchScope = scope
        searchBar.placeholder = scope == .places ? "Search places..." : "Search circles..."
        updateSearchScopeMenu()
        // Re-run the active search under the new scope
        filteredPlaces = []
        filteredCircles = []
        if let text = searchBar.text, !text.isEmpty {
            self.searchBar(searchBar, textDidChange: text)
        } else {
            hideSearchResults()
        }
    }

    func filterCirclesForSearch(_ searchText: String) {
        filteredCircles = circles.filter { circle in
            circle.name.localizedCaseInsensitiveContains(searchText) ||
            (circle.description ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    // Mirrors PlaceSearchable.showSearchResults but sized to circle results
    func showCircleSearchResults() {
        let height = CGFloat(min(filteredCircles.count, 5)) * 60
        searchResultsTableView.isHidden = false
        searchResultsHeightConstraint?.constant = height
        UIView.animate(withDuration: 0.3) {
            self.searchResultsTableView.alpha = 1
            self.view.layoutIfNeeded()
        }
        searchResultsTableView.reloadData()
    }
}
