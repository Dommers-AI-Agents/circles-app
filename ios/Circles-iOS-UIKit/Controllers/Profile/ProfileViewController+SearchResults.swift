import UIKit
import MapKit
import CoreLocation
import PhotosUI

// Search-results table view and content-upload delegate for ProfileViewController. Extracted from the main controller (Wave 4).

// MARK: - UITableViewDataSource & UITableViewDelegate for Search Results
extension ProfileViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == searchResultsTableView {
            if profileSearchScope == .circles {
                return isSearching ? filteredCircles.count : 0
            }
            return numberOfRowsInSearchResults()
        }
        if tableView == mapPlacesListTableView {
            return mapDistanceSortedPlaces.count
        }
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if tableView == searchResultsTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
            if profileSearchScope == .circles {
                configureCircleSearchResultCell(cell, at: indexPath)
            } else {
                configureSearchResultCell(cell, at: indexPath)
            }
            return cell
        }
        if tableView == mapPlacesListTableView {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ProfilePlaceListCell", for: indexPath) as! QuickAccessPlaceCell
            guard indexPath.row < mapDistanceSortedPlaces.count else { return cell }
            let entry = mapDistanceSortedPlaces[indexPath.row]
            let distanceText = entry.distance.map { mapListDistanceFormatter.string(fromDistance: $0) }
            cell.configure(with: entry.place, isSelected: false, distanceText: distanceText)
            return cell
        }
        return UITableViewCell()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView == searchResultsTableView {
            if profileSearchScope == .circles {
                handleCircleSearchResultSelection(at: indexPath)
            } else {
                handleSearchResultSelection(at: indexPath)
            }
        }
        if tableView == mapPlacesListTableView {
            tableView.deselectRow(at: indexPath, animated: true)
            guard indexPath.row < mapDistanceSortedPlaces.count else { return }
            // Same destination as tapping a pin's callout on this map
            let placeDetailVC = PlaceDetailViewController(place: mapDistanceSortedPlaces[indexPath.row].place)
            navigationController?.pushViewController(placeDetailVC, animated: true)
        }
    }
}

// MARK: - FullScreenMapViewControllerDelegate
extension ProfileViewController {
    func mapViewController(_ controller: FullScreenMapViewController, didSelectPlace place: Place) {
        controller.dismiss(animated: true) {
            let placeDetailVC = PlaceDetailViewController(place: place)
            self.navigationController?.pushViewController(placeDetailVC, animated: true)
        }
    }
}

// MARK: - ContentUploadDelegate
extension ProfileViewController: ContentUploadDelegate {
    func contentUploadDidFinish(with moment: PlaceMoment) {
        showSuccess("Moment shared successfully!")
        
        // Refresh videos/moments if on Moments tab
        if contentTypeSegmentedControl.selectedSegmentIndex == 1 {
            fetchUserVideos() // This will reload the moments collection
        }
        
        // Track activity
        NotificationCenter.default.post(
            name: Notification.Name("MomentUploaded"),
            object: nil,
            userInfo: ["moment": moment]
        )
        
        // Navigate to home tab to show the new moment in the feed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            // Find the tab bar controller and switch to home tab
            if let tabBarController = self?.tabBarController {
                Logger.debug("🏠 Navigating to home tab after successful moment upload")
                tabBarController.selectedIndex = 0 // Home tab is index 0
            } else if let navController = self?.navigationController,
                      let tabBarController = navController.tabBarController {
                Logger.debug("🏠 Navigating to home tab via nav controller after successful moment upload")
                tabBarController.selectedIndex = 0
            } else {
                Logger.debug("⚠️ Could not find tab bar controller for navigation")
            }
        }
    }
    
    func contentUploadDidCancel() {
        // User cancelled - nothing to do
    }
}

