import Foundation
import UIKit
import MapKit
import CoreLocation
import GooglePlaces

// Unified service that uses Apple Maps for search and Google Places only for photos
class PlaceDetailsService {
    static let shared = PlaceDetailsService()
    
    private let placesClient: GMSPlacesClient
    
    private init() {
        self.placesClient = GMSPlacesClient.shared()
    }
    
    // MARK: - Hybrid Place Details
    
    /// Get place details from Apple Maps, then enrich with Google photos if available
    func getEnrichedPlaceDetails(for mapItem: MKMapItem, completion: @escaping (Result<EnrichedPlaceDetails, Error>) -> Void) {
        // First, try to find a matching Google Place ID for photo loading
        findGooglePlaceId(for: mapItem) { [weak self] googlePlaceId in
            guard let self = self else { return }
            
            var enrichedDetails = EnrichedPlaceDetails(mapItem: mapItem)
            enrichedDetails.googlePlaceId = googlePlaceId
            
            // If we found a Google Place ID, try to load photos
            if let placeId = googlePlaceId {
                self.loadGooglePhotos(placeId: placeId) { photos in
                    enrichedDetails.googlePhotos = photos
                    completion(.success(enrichedDetails))
                }
            } else {
                // No Google Place ID found, return details without photos
                completion(.success(enrichedDetails))
            }
        }
    }
    
    // MARK: - Google Place ID Lookup
    
    private func findGooglePlaceId(for mapItem: MKMapItem, completion: @escaping (String?) -> Void) {
        guard let name = mapItem.name,
              let location = mapItem.placemark.location else {
            completion(nil)
            return
        }
        
        // Create a search filter for the location
        let filter = GMSAutocompleteFilter()
        filter.type = .establishment
        
        // Search within a small radius of the Apple Maps location
        // Create bounds around the coordinate (approximately 100 meter radius)
        let latDelta = 0.001 // roughly 100 meters
        let lonDelta = 0.001
        
        let northEast = CLLocationCoordinate2D(
            latitude: location.coordinate.latitude + latDelta,
            longitude: location.coordinate.longitude + lonDelta
        )
        let southWest = CLLocationCoordinate2D(
            latitude: location.coordinate.latitude - latDelta,
            longitude: location.coordinate.longitude - lonDelta
        )
        
        filter.locationBias = GMSPlaceRectangularLocationOption(northEast, southWest)
        
        // Search for the place by name
        placesClient.findAutocompletePredictions(
            fromQuery: name,
            filter: filter,
            sessionToken: nil
        ) { predictions, error in
            guard let predictions = predictions,
                  !predictions.isEmpty else {
                completion(nil)
                return
            }
            
            // Try to find the best match
            // First, look for exact name match
            if let exactMatch = predictions.first(where: { 
                $0.attributedPrimaryText.string.lowercased() == name.lowercased() 
            }) {
                completion(exactMatch.placeID)
                return
            }
            
            // Otherwise, use the first result if it's close enough
            if let firstPrediction = predictions.first {
                // Check if the location is within ~100 meters
                self.placesClient.fetchPlace(
                    fromPlaceID: firstPrediction.placeID,
                    placeFields: [.coordinate],
                    sessionToken: nil
                ) { place, _ in
                    guard let place = place else {
                        completion(nil)
                        return
                    }
                    
                    let distance = location.distance(from: CLLocation(
                        latitude: place.coordinate.latitude,
                        longitude: place.coordinate.longitude
                    ))
                    
                    // If within 100 meters, consider it a match
                    if distance < 100 {
                        completion(firstPrediction.placeID)
                    } else {
                        completion(nil)
                    }
                }
            } else {
                completion(nil)
            }
        }
    }
    
    // MARK: - Google Photos Loading
    
    private func loadGooglePhotos(placeId: String, completion: @escaping ([GMSPlacePhotoMetadata]) -> Void) {
        placesClient.fetchPlace(
            fromPlaceID: placeId,
            placeFields: [.photos],
            sessionToken: nil
        ) { place, error in
            guard let place = place,
                  let photos = place.photos else {
                completion([])
                return
            }
            
            completion(photos)
        }
    }
    
    // MARK: - Photo Loading
    
    func loadPhoto(from metadata: GMSPlacePhotoMetadata, maxSize: CGSize, completion: @escaping (Result<UIImage, Error>) -> Void) {
        placesClient.loadPlacePhoto(metadata) { photo, error in
            if let error = error {
                completion(.failure(error))
            } else if let photo = photo {
                completion(.success(photo))
            } else {
                completion(.failure(NSError(domain: "PlaceDetailsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to load photo"])))
            }
        }
    }
}

// MARK: - Enriched Place Details

struct EnrichedPlaceDetails {
    let mapItem: MKMapItem
    var googlePlaceId: String?
    var googlePhotos: [GMSPlacePhotoMetadata] = []
    
    var name: String? {
        return mapItem.name
    }
    
    var address: String {
        return mapItem.placemark.formattedAddress
    }
    
    var coordinate: CLLocationCoordinate2D {
        return mapItem.placemark.coordinate
    }
    
    var phoneNumber: String? {
        return mapItem.phoneNumber
    }
    
    var url: URL? {
        return mapItem.url
    }
    
    var category: PlaceCategory {
        guard let poiCategory = mapItem.pointOfInterestCategory else {
            return .other
        }
        
        switch poiCategory {
        case .restaurant: return .restaurant
        case .cafe: return .cafe
        case .nightlife, .brewery, .winery: return .bar
        case .hotel, .campground: return .hotel
        case .store, .foodMarket: return .retail
        case .gasStation, .evCharger, .carRental, .laundry, .postOffice: return .service
        case .bank, .atm: return .finance
        case .pharmacy, .hospital: return .healthcare
        case .parking, .publicTransport: return .transport
        case .school, .university, .library: return .education
        case .movieTheater, .theater: return .entertainment
        case .museum, .zoo, .aquarium, .amusementPark: return .attraction
        case .park, .beach, .nationalPark, .marina: return .outdoor
        case .stadium: return .entertainment
        default:
            if #available(iOS 18.0, *) {
                switch poiCategory {
                case .miniGolf: return .entertainment
                case .castle, .landmark: return .attraction
                default: return .other
                }
            } else {
                return .other
            }
        }
    }
}