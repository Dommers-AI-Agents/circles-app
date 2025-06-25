import Foundation
import GooglePlaces
import CoreLocation

class GooglePlacesService {
    static let shared = GooglePlacesService()
    
    private let placesClient: GMSPlacesClient
    
    private init() {
        self.placesClient = GMSPlacesClient.shared()
    }
    
    // MARK: - Autocomplete Search
    
    func searchPlaces(query: String, location: CLLocation? = nil, completion: @escaping (Result<[GMSAutocompletePrediction], Error>) -> Void) {
        let filter = GMSAutocompleteFilter()
        filter.types = ["establishment"] // Search for businesses/places
        
        // Apply location bias if location is provided
        if let location = location {
            let coordinate = location.coordinate
            // Create a rectangular bias around the user's location (approximately 20km x 20km)
            filter.locationBias = GMSPlaceRectangularLocationOption(
                CLLocationCoordinate2D(latitude: coordinate.latitude - 0.1, longitude: coordinate.longitude - 0.1),
                CLLocationCoordinate2D(latitude: coordinate.latitude + 0.1, longitude: coordinate.longitude + 0.1)
            )
        }
        
        placesClient.findAutocompletePredictions(
            fromQuery: query,
            filter: filter,
            sessionToken: nil,
            callback: { predictions, error in
                if let error = error {
                    completion(.failure(error))
                } else if let predictions = predictions {
                    completion(.success(predictions))
                } else {
                    completion(.success([]))
                }
            }
        )
    }
    
    // MARK: - Category Search with Location Context
    
    func searchPlacesByCategory(category: String, center: CLLocationCoordinate2D, radiusInMeters: Double, completion: @escaping (Result<[GMSAutocompletePrediction], Error>) -> Void) {
        let filter = GMSAutocompleteFilter()
        // Don't set filter type for category searches - let it search all place types
        
        // Calculate bounds based on radius
        let latDelta = radiusInMeters / 111111.0
        let lonDelta = radiusInMeters / (111111.0 * cos(center.latitude * .pi / 180))
        
        let northEast = CLLocationCoordinate2D(
            latitude: center.latitude + latDelta,
            longitude: center.longitude + lonDelta
        )
        let southWest = CLLocationCoordinate2D(
            latitude: center.latitude - latDelta,
            longitude: center.longitude - lonDelta
        )
        
        print("📍 GooglePlacesService - Searching for: '\(category)'")
        print("📍 Center: \(center.latitude), \(center.longitude)")
        print("📍 Bounds: NE(\(northEast.latitude), \(northEast.longitude)) SW(\(southWest.latitude), \(southWest.longitude))")
        
        // Use location restriction instead of bias for more focused results
        filter.locationRestriction = GMSPlaceRectangularLocationOption(southWest, northEast)
        
        placesClient.findAutocompletePredictions(
            fromQuery: category,
            filter: filter,
            sessionToken: nil,
            callback: { predictions, error in
                if let error = error {
                    print("❌ GooglePlacesService - Error: \(error)")
                    completion(.failure(error))
                } else if let predictions = predictions {
                    print("✅ GooglePlacesService - Found \(predictions.count) predictions")
                    // Filter to only show establishments
                    let establishmentPredictions = predictions.filter { prediction in
                        // Most business places will have these types
                        let establishmentTypes = ["establishment", "point_of_interest", "food", "restaurant", "cafe", "bar", 
                                                 "lodging", "store", "shopping_mall", "park", "tourist_attraction"]
                        return prediction.types.contains(where: { establishmentTypes.contains($0) })
                    }
                    print("🏪 Filtered to \(establishmentPredictions.count) establishment predictions")
                    completion(.success(establishmentPredictions))
                } else {
                    print("⚠️ GooglePlacesService - No predictions found")
                    completion(.success([]))
                }
            }
        )
    }
    
    // MARK: - Fetch Place Details
    
    func fetchPlaceDetails(placeID: String, completion: @escaping (Result<GMSPlace, Error>) -> Void) {
        let fields: GMSPlaceField = [
            .name,
            .placeID,
            .coordinate,
            .formattedAddress,
            .phoneNumber,
            .website,
            .rating,
            .userRatingsTotal,
            .priceLevel,
            .types,
            .photos,
            .openingHours,
            .businessStatus
        ]
        
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
    
    // Fetch place details with reviews
    func fetchPlaceDetailsWithReviews(placeID: String, completion: @escaping (Result<GMSPlace, Error>) -> Void) {
        let fields: GMSPlaceField = [
            .name,
            .placeID,
            .coordinate,
            .formattedAddress,
            .phoneNumber,
            .website,
            .rating,
            .userRatingsTotal,
            .priceLevel,
            .types,
            .photos,
            .openingHours,
            .businessStatus
            // Note: Reviews are not available through GMSPlaceField in iOS SDK
            // They must be fetched through the Google Places Web API
        ]
        
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
    
    // MARK: - Load Place Photo
    
    func loadPhoto(from metadata: GMSPlacePhotoMetadata, maxSize: CGSize = CGSize(width: 800, height: 600), completion: @escaping (Result<UIImage, Error>) -> Void) {
        placesClient.loadPlacePhoto(metadata) { photo, error in
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
    
    // Convenience method to match the API used in AddPlaceViewGoogle
    func loadPlacePhoto(photoReference: GMSPlacePhotoMetadata, completion: @escaping (UIImage?) -> Void) {
        loadPhoto(from: photoReference) { result in
            switch result {
            case .success(let image):
                completion(image)
            case .failure:
                completion(nil)
            }
        }
    }
    
    // MARK: - Get Current Location Places
    
    func findNearbyPlaces(location: CLLocation, radius: Double = 500, types: [String]? = nil, completion: @escaping (Result<[GMSPlace], Error>) -> Void) {
        // Note: Google Places SDK doesn't have a direct nearby search in iOS SDK
        // We'll use the autocomplete with location bias as a workaround
        // For a proper nearby search, you would need to use the Places API web service
        
        completion(.failure(NSError(
            domain: "GooglePlacesService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Nearby search not implemented in this version"]
        )))
    }
    
    // MARK: - Helper Methods
    
    func mapGooglePlaceTypeToCategory(_ types: [String]?) -> PlaceCategory {
        guard let types = types else { return .other }
        
        // Map Google place types to our categories
        if types.contains("restaurant") { return .restaurant }
        if types.contains("cafe") { return .cafe }
        if types.contains("bar") || types.contains("night_club") { return .bar }
        if types.contains("lodging") || types.contains("hotel") { return .hotel }
        if types.contains("store") || types.contains("shopping_mall") { return .retail }
        if types.contains("health") || types.contains("hospital") || types.contains("doctor") { return .healthcare }
        if types.contains("gym") || types.contains("spa") { return .fitness }
        if types.contains("school") || types.contains("university") { return .education }
        if types.contains("park") || types.contains("campground") { return .outdoor }
        if types.contains("transit_station") || types.contains("gas_station") { return .transport }
        if types.contains("bank") || types.contains("atm") { return .finance }
        if types.contains("movie_theater") || types.contains("museum") || types.contains("stadium") { return .entertainment }
        if types.contains("tourist_attraction") || types.contains("point_of_interest") { return .attraction }
        
        return .other
    }
    
    func mapPriceLevel(_ priceLevel: GMSPlacesPriceLevel) -> PriceLevel {
        switch priceLevel {
        case .free: return .free
        case .cheap: return .inexpensive
        case .medium: return .moderate
        case .high: return .expensive
        case .expensive: return .veryExpensive
        @unknown default: return .moderate
        }
    }
    
    // MARK: - Geocoding
    
    func geocodeAddress(_ address: String, completion: @escaping (Result<GooglePlaceDetails, Error>) -> Void) {
        // Use Google Maps Geocoding API
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String else {
            completion(.failure(NSError(domain: "GooglePlacesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Google Maps API key not found"])))
            return
        }
        
        // Create the geocoding URL
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/geocode/json")
        components?.queryItems = [
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "key", value: apiKey)
        ]
        
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "GooglePlacesService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "GooglePlacesService", code: -3, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                
                guard let status = json?["status"] as? String else {
                    completion(.failure(NSError(domain: "GooglePlacesService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                    return
                }
                
                if status != "OK" {
                    let errorMessage = json?["error_message"] as? String ?? "Geocoding failed with status: \(status)"
                    completion(.failure(NSError(domain: "GooglePlacesService", code: -5, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                    return
                }
                
                guard let results = json?["results"] as? [[String: Any]], let firstResult = results.first else {
                    completion(.failure(NSError(domain: "GooglePlacesService", code: -6, userInfo: [NSLocalizedDescriptionKey: "No results found"])))
                    return
                }
                
                // Extract place details from geocoding result
                let placeID = firstResult["place_id"] as? String ?? UUID().uuidString
                let formattedAddress = firstResult["formatted_address"] as? String ?? address
                
                // Extract location
                guard let geometry = firstResult["geometry"] as? [String: Any],
                      let location = geometry["location"] as? [String: Double],
                      let lat = location["lat"],
                      let lng = location["lng"] else {
                    completion(.failure(NSError(domain: "GooglePlacesService", code: -7, userInfo: [NSLocalizedDescriptionKey: "Location not found"])))
                    return
                }
                
                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                
                // Extract types
                let types = firstResult["types"] as? [String] ?? ["geocoded_address"]
                
                // Extract address components for a better name
                var placeName = address
                if let addressComponents = firstResult["address_components"] as? [[String: Any]] {
                    // Try to get street number and route for a better name
                    var streetNumber: String?
                    var route: String?
                    
                    for component in addressComponents {
                        if let componentTypes = component["types"] as? [String] {
                            if componentTypes.contains("street_number") {
                                streetNumber = component["short_name"] as? String
                            } else if componentTypes.contains("route") {
                                route = component["short_name"] as? String
                            }
                        }
                    }
                    
                    if let streetNumber = streetNumber, let route = route {
                        placeName = "\(streetNumber) \(route)"
                    } else if let route = route {
                        placeName = route
                    }
                }
                
                // Create GooglePlaceDetails object
                let placeDetails = GooglePlaceDetails(
                    placeID: placeID,
                    name: placeName,
                    address: formattedAddress,
                    coordinate: coordinate,
                    phoneNumber: nil,
                    website: nil,
                    rating: nil,
                    userRatingsTotal: 0,
                    priceLevel: nil,
                    types: types,
                    photos: [],
                    openingHours: nil,
                    isOpen: nil
                )
                
                completion(.success(placeDetails))
                
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}