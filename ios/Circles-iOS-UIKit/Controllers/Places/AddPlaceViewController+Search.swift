import UIKit
import MapKit
import CoreLocation
import PhotosUI

// Search bar, Apple Maps search, and completer delegates for AddPlaceViewController. Extracted from the main controller (Wave 4).

// MARK: - UISearchBarDelegate

extension AddPlaceViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        // Cancel previous timer
        searchTimer?.invalidate()
        
        // Hide results if search is empty
        if searchText.isEmpty {
            searchResults = []
            searchResultsTableView.reloadData()
            searchResultsTableView.isHidden = true
            return
        }
        
        // Show table view immediately for better UX
        searchResultsTableView.isHidden = false
        
        // Debounce search by 0.3 seconds
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.performAppleMapsSearch(searchText)
        }
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        // Reset category search flag when user starts typing
        hasSearchedCategory = false
        
        if !searchBar.text!.isEmpty {
            searchResultsTableView.isHidden = false
        }
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - Apple Maps Search

extension AddPlaceViewController {
    func performAppleMapsSearch(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            showPlaceTypeSuggestion = false
            searchResultsTableView.reloadData()
            return
        }
        
        // Check if query looks like a place type (simple words without numbers or specific addresses)
        let isLikelyPlaceType = !query.contains(where: { $0.isNumber }) && 
                               !query.lowercased().contains("street") && 
                               !query.lowercased().contains("ave") &&
                               !query.lowercased().contains("road") &&
                               !query.contains(",") &&
                               query.split(separator: " ").count <= 3
        
        showPlaceTypeSuggestion = isLikelyPlaceType
        placeTypeSuggestionQuery = query
        
        // Set search region based on current map view
        if let userLocation = locationManager.location {
            searchCompleter.region = MKCoordinateRegion(
                center: userLocation.coordinate,
                latitudinalMeters: 40000, // ~25 miles
                longitudinalMeters: 40000
            )
        } else {
            searchCompleter.region = mapView.region
        }
        
        searchCompleter.queryFragment = query
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension AddPlaceViewController: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results
        searchResultsTableView.reloadData()
        Logger.debug("✅ Apple Maps found \(searchResults.count) results")
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Logger.debug("🔴 Apple Maps search error: \(error.localizedDescription)")
        searchResults = []
        searchResultsTableView.reloadData()
    }
}

