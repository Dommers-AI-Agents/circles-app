import UIKit
import MapKit
import CoreLocation
import PhotosUI

// Circle search bar and search helpers for ProfileViewController. Extracted from the main controller (Wave 4).

// MARK: - UISearchBarDelegate
extension ProfileViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if profileSearchScope == .circles {
            if searchText.isEmpty {
                isSearching = false
                filteredCircles = []
                hideSearchResults()
            } else {
                isSearching = true
                filterCirclesForSearch(searchText)
                if filteredCircles.isEmpty {
                    hideSearchResults()
                } else {
                    showCircleSearchResults()
                }
            }
            circlesCollectionView.reloadData()
            return
        }
        // Call the protocol's default implementation
        (self as PlaceSearchable).searchBar(searchBar, textDidChange: searchText)
        // Update collection view to show/hide content during search
        circlesCollectionView.reloadData()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        filteredCircles = []
        // Call the protocol's default implementation
        (self as PlaceSearchable).searchBarCancelButtonClicked(searchBar)
        // Update collection view after clearing search
        circlesCollectionView.reloadData()
        // Ensure keyboard is dismissed
        view.endEditing(true)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // Call the protocol's default implementation
        (self as PlaceSearchable).searchBarSearchButtonClicked(searchBar)
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        // Call the protocol's default implementation
        (self as PlaceSearchable).searchBarTextDidBeginEditing(searchBar)
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        // Call the protocol's default implementation
        (self as PlaceSearchable).searchBarTextDidEndEditing(searchBar)
    }
}

// MARK: - PlaceSearchable Navigation
extension ProfileViewController {
    func navigateToPlace(_ place: Place) {
        // Find the circle this place belongs to
        guard let circle = circles.first(where: { $0.id == place.circleId }) else {
            Logger.debug("⚠️ Could not find circle for place: \(place.name)")
            return
        }
        
        let placeDetailVC = PlaceDetailViewController(place: place, circle: circle)
        navigationController?.pushViewController(placeDetailVC, animated: true)
    }
}

// MARK: - Circle Search Results
extension ProfileViewController {
    func configureCircleSearchResultCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard indexPath.row < filteredCircles.count else { return }

        let circle = filteredCircles[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = circle.name
        let placeCount = circle.placesCount ?? circle.places?.count ?? 0
        content.secondaryText = "\(placeCount) place\(placeCount == 1 ? "" : "s")"
        content.image = UIImage(systemName: "circle.grid.2x2.fill")
        content.imageProperties.tintColor = Constants.Colors.primary
        cell.contentConfiguration = content
    }

    func handleCircleSearchResultSelection(at indexPath: IndexPath) {
        guard indexPath.row < filteredCircles.count else { return }

        let circle = filteredCircles[indexPath.row]

        // Clear search (same reset as the places path)
        searchBar.text = ""
        searchBar.resignFirstResponder()
        isSearching = false
        filteredCircles = []
        hideSearchResults()

        let circleDetailVC = CircleDetailViewController(circle: circle)
        navigationController?.pushViewController(circleDetailVC, animated: true)
    }
}
