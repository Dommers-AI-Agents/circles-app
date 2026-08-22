import Foundation
import GooglePlaces
import CoreLocation

// ⚠️ CRITICAL: ONLY USE THIS SERVICE FOR FETCHING PHOTOS ⚠️
// 
// IMPORTANT: Due to cost considerations, Google Places API should ONLY be used for:
// - Fetching place photos (loadPhoto method)
// 
// DO NOT USE for:
// - Place search (use Apple Maps MKLocalSearch instead)
// - Geocoding (use Apple Maps CLGeocoder instead)
// - Place details (use Apple Maps MKMapItem instead)
// - Autocomplete (use Apple Maps MKLocalSearchCompleter instead)
// 
// See APIUsageGuidelines.md for full policy details

class GooglePlacesService {
    static let shared = GooglePlacesService()
    
    private let placesClient: GMSPlacesClient
    
    private init() {
        self.placesClient = GMSPlacesClient.shared()
    }
    
    // MARK: - Photo Loading (ONLY ALLOWED GOOGLE PLACES USAGE)
    
    /// Load a place photo from Google Places API
    /// This is the ONLY acceptable use of Google Places API in this app.
    /// maxSize is honored via the constrained variant — the unconstrained
    /// loadPlacePhoto fetched MAX resolution regardless of the parameter,
    /// which downloaded multi-MB originals to fill small cells.
    func loadPhoto(from metadata: GMSPlacePhotoMetadata, maxSize: CGSize = CGSize(width: 800, height: 600), completion: @escaping (Result<UIImage, Error>) -> Void) {
        placesClient.loadPlacePhoto(
            metadata,
            constrainedTo: maxSize,
            scale: UIScreen.main.scale
        ) { photo, error in
            if let error = error {
                completion(.failure(error))
            } else if let photo = photo {
                completion(.success(photo))
            } else {
                completion(.failure(NSError(
                    domain: "GooglePlacesService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to load photo"]
                )))
            }
        }
    }
    
    // MARK: - Place ID + photo metadata (the once-per-venue purchase)

    @available(*, deprecated, message: "Use Apple Maps MKMapItem for place details. This method now only fetches photos for backward compatibility.")
    func fetchPlaceDetails(placeID: String, completion: @escaping (Result<GMSPlace, Error>) -> Void) {
        Logger.debug("⚠️ DEPRECATED: fetchPlaceDetails called. Only fetching photos for backward compatibility.")
        
        // Fetch photos, coordinate, rating — plus the editorial summary, the
        // only real venue description Google offers (rating already bills the
        // Atmosphere SKU, so the summary adds no incremental API cost)
        let fields: GMSPlaceField = [.photos, .placeID, .coordinate, .rating, .userRatingsTotal, .editorialSummary]
        
        placesClient.fetchPlace(
            fromPlaceID: placeID,
            placeFields: fields,
            sessionToken: nil
        ) { place, error in
            if let error = error {
                completion(.failure(error))
            } else if let place = place {
                completion(.success(place))
            } else {
                completion(.failure(NSError(
                    domain: "GooglePlacesService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Place not found"]
                )))
            }
        }
    }
    
    @available(*, deprecated, message: "Use Apple Maps MKLocalSearch instead. See APIUsageGuidelines.md")
    func searchPlaceByNameAndLocation(name: String, coordinate: CLLocationCoordinate2D, address: String? = nil, completion: @escaping (Result<GMSAutocompletePrediction?, Error>) -> Void) {
        Logger.debug("⚠️ NOTE: Using Google Places ONLY to get place ID for photo fetching. All other data comes from Apple Maps.")
        
        // Create a search token
        let token = GMSAutocompleteSessionToken()
        
        // Create location bias for the search
        let northEast = CLLocationCoordinate2D(
            latitude: coordinate.latitude + 0.01,
            longitude: coordinate.longitude + 0.01
        )
        let southWest = CLLocationCoordinate2D(
            latitude: coordinate.latitude - 0.01,
            longitude: coordinate.longitude - 0.01
        )
        
        // Create filter with location bias
        let filter = GMSAutocompleteFilter()
        filter.locationBias = GMSPlaceRectangularLocationOption(northEast, southWest)
        
        // Build search query - include address if provided for better accuracy
        var searchQuery = name
        if let address = address, !address.isEmpty {
            searchQuery = "\(name), \(address)"
            Logger.debug("🔍 Enhanced search query: \(searchQuery)")
        }
        
        // Search for the place
        placesClient.findAutocompletePredictions(
            fromQuery: searchQuery,
            filter: filter,
            sessionToken: token
        ) { predictions, error in
            if let error = error {
                Logger.debug("❌ Google Places search error: \(error)")
                completion(.failure(error))
                return
            }
            
            // Find the best match based on name similarity and distance
            var bestMatch: GMSAutocompletePrediction? = nil
            
            if let predictions = predictions, !predictions.isEmpty {
                Logger.debug("📍 Found \(predictions.count) predictions for '\(searchQuery)'")
                
                // Log all predictions for debugging
                for (index, prediction) in predictions.enumerated() {
                    Logger.debug("  \(index + 1). \(prediction.attributedPrimaryText.string) - \(prediction.attributedSecondaryText?.string ?? "")")
                }
                
                // First try to find exact name match
                bestMatch = predictions.first { prediction in
                    let predictionName = prediction.attributedPrimaryText.string.lowercased()
                    let searchName = name.lowercased()
                    return predictionName == searchName || predictionName.contains(searchName)
                }
                
                // If no exact match, use the first result (closest based on location bias)
                if bestMatch == nil {
                    bestMatch = predictions.first
                    Logger.debug("⚠️ No exact name match found, using closest result based on location")
                } else {
                    Logger.debug("✅ Found exact match: \(bestMatch!.attributedPrimaryText.string)")
                }
            }
            
            completion(.success(bestMatch))
        }
    }
}