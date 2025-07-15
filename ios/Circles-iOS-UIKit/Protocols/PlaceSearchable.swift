import UIKit

// MARK: - PlaceSearchable Protocol
protocol PlaceSearchable: UIViewController, UISearchBarDelegate {
    var allPlaces: [Place] { get set }
    var filteredPlaces: [Place] { get set }
    var isSearching: Bool { get set }
    var searchResultsTableView: UITableView { get }
    var searchResultsHeightConstraint: NSLayoutConstraint? { get set }
    var searchBar: UISearchBar { get }
    
    // Optional: For getting circles to show in search results
    var circles: [Circle] { get }
    
    func showSearchResults()
    func hideSearchResults()
    func filterPlaces(searchText: String)
    func navigateToPlace(_ place: Place)
}

// MARK: - Default Implementations
extension PlaceSearchable {
    
    func showSearchResults() {
        let maxVisibleResults = 5
        let cellHeight: CGFloat = 60
        let numberOfResults = min(filteredPlaces.count, maxVisibleResults)
        let height = CGFloat(numberOfResults) * cellHeight
        
        searchResultsTableView.isHidden = false
        searchResultsHeightConstraint?.constant = height
        
        UIView.animate(withDuration: 0.3) {
            self.searchResultsTableView.alpha = 1
            self.view.layoutIfNeeded()
        }
        
        searchResultsTableView.reloadData()
    }
    
    func hideSearchResults() {
        UIView.animate(withDuration: 0.3) {
            self.searchResultsTableView.alpha = 0
            self.searchResultsHeightConstraint?.constant = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.searchResultsTableView.isHidden = true
        }
    }
    
    func filterPlaces(searchText: String) {
        filteredPlaces = allPlaces.filter { place in
            place.name.localizedCaseInsensitiveContains(searchText) ||
            place.address.localizedCaseInsensitiveContains(searchText) ||
            (place.description ?? "").localizedCaseInsensitiveContains(searchText) ||
            (place.notes ?? "").localizedCaseInsensitiveContains(searchText) ||
            (place.publicNotes ?? "").localizedCaseInsensitiveContains(searchText) ||
            (place.privateNotes ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - UISearchBarDelegate Default Implementation
extension PlaceSearchable {
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            isSearching = false
            filteredPlaces = []
            hideSearchResults()
        } else {
            isSearching = true
            filterPlaces(searchText: searchText)
            
            if !filteredPlaces.isEmpty {
                showSearchResults()
            } else {
                hideSearchResults()
            }
        }
        
        // Let each view controller handle its own empty state updates
        // by overriding this method if needed
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        isSearching = false
        filteredPlaces = []
        hideSearchResults()
        
        // Let each view controller handle its own empty state updates
        // by overriding this method if needed
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }
}

// MARK: - Search Results Table View Default Implementation
extension PlaceSearchable {
    
    func numberOfRowsInSearchResults() -> Int {
        return isSearching ? filteredPlaces.count : 0
    }
    
    // Default implementation - can be overridden by conforming classes
    func configureSearchResultCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard indexPath.row < filteredPlaces.count else { return }
        
        let place = filteredPlaces[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = place.name
        
        // Show address and circle name if available
        if let circle = circles.first(where: { $0.id == place.circleId }) {
            content.secondaryText = "\(place.address) • \(circle.name)"
        } else {
            content.secondaryText = place.address
        }
        
        content.image = UIImage(systemName: "mappin.circle.fill")
        content.imageProperties.tintColor = Constants.Colors.primary
        
        cell.contentConfiguration = content
    }
    
    func handleSearchResultSelection(at indexPath: IndexPath) {
        guard indexPath.row < filteredPlaces.count else { return }
        
        let place = filteredPlaces[indexPath.row]
        
        // Clear search
        searchBar.text = ""
        searchBar.resignFirstResponder()
        isSearching = false
        filteredPlaces = []
        hideSearchResults()
        
        // Navigate to place (each controller implements this differently)
        navigateToPlace(place)
    }
}