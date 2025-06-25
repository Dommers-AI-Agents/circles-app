import Foundation
import Combine
import GooglePlaces
import CoreLocation

@MainActor
class GooglePlaceSearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var searchResults: [GooglePlacePrediction] = []
    @Published var selectedPlace: GooglePlaceDetails?
    @Published var isSearching = false
    @Published var isLoadingDetails = false
    @Published var errorMessage: String?
    
    private var searchCancellable: AnyCancellable?
    private let googlePlacesService = GooglePlacesService.shared
    private let locationService = LocationService.shared
    
    init() {
        setupSearchListener()
    }
    
    private func setupSearchListener() {
        searchCancellable = $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                if query.isEmpty {
                    self?.searchResults = []
                } else {
                    self?.searchPlaces(query: query)
                }
            }
    }
    
    func search() {
        searchPlaces(query: searchText)
    }
    
    func searchNearLocation(query: String, location: CLLocation? = nil) {
        // If we have a location, add context to the query
        var enhancedQuery = query
        if let location = location ?? locationService.lastKnownLocation {
            // Get city/region name if possible (this is a simplified approach)
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { placemarks, _ in
                if let placemark = placemarks?.first {
                    let locationContext = [placemark.locality, placemark.administrativeArea]
                        .compactMap { $0 }
                        .joined(separator: ", ")
                    
                    if !locationContext.isEmpty && !query.lowercased().contains(locationContext.lowercased()) {
                        // Add location context if not already in query
                        enhancedQuery = "\(query) \(locationContext)"
                    }
                }
                self.searchPlaces(query: enhancedQuery)
            }
        } else {
            searchPlaces(query: query)
        }
    }
    
    private func searchPlaces(query: String) {
        isSearching = true
        errorMessage = nil
        
        // Get current location for better results
        locationService.getCurrentLocation { [weak self] location in
            self?.googlePlacesService.searchPlaces(query: query, location: location) { result in
                DispatchQueue.main.async {
                    self?.isSearching = false
                    
                    switch result {
                    case .success(let predictions):
                        self?.searchResults = predictions.map { GooglePlacePrediction(from: $0) }
                    case .failure(let error):
                        self?.errorMessage = error.localizedDescription
                        self?.searchResults = []
                    }
                }
            }
        }
    }
    
    func selectPlace(_ prediction: GooglePlacePrediction) {
        isLoadingDetails = true
        errorMessage = nil
        
        googlePlacesService.fetchPlaceDetails(placeID: prediction.placeID) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingDetails = false
                
                switch result {
                case .success(let place):
                    self?.selectedPlace = GooglePlaceDetails(from: place)
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func clearSelection() {
        selectedPlace = nil
        searchText = ""
        searchResults = []
    }
    
    func fetchPlaceDetails(for prediction: GooglePlacePrediction, completion: @escaping (GooglePlaceDetails?) -> Void) {
        googlePlacesService.fetchPlaceDetails(placeID: prediction.placeID) { result in
            switch result {
            case .success(let place):
                completion(GooglePlaceDetails(from: place))
            case .failure:
                completion(nil)
            }
        }
    }
    
    func selectPlace(byID placeID: String) {
        // Find the prediction with this placeID and select it
        if let prediction = searchResults.first(where: { $0.placeID == placeID }) {
            selectPlace(prediction)
        }
    }
    
    func createPlaceFromAddress(_ address: String) {
        isLoadingDetails = true
        errorMessage = nil
        
        // Use Google's Geocoding API
        googlePlacesService.geocodeAddress(address) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingDetails = false
                
                switch result {
                case .success(let placeDetails):
                    self?.selectedPlace = placeDetails
                case .failure(let error):
                    self?.errorMessage = "Could not find location for this address: \(error.localizedDescription)"
                }
            }
        }
    }
}