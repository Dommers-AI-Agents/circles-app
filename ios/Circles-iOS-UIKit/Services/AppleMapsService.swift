import Foundation
import MapKit
import CoreLocation

class AppleMapsService {
    static let shared = AppleMapsService()
    
    private init() {}
    
    // MARK: - Search
    
    func searchPlaces(query: String, region: MKCoordinateRegion? = nil, completion: @escaping (Result<[MKMapItem], Error>) -> Void) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        if let region = region {
            request.region = region
        }
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let error = error {
                completion(.failure(error))
            } else if let mapItems = response?.mapItems {
                completion(.success(mapItems))
            } else {
                completion(.success([]))
            }
        }
    }
    
    // MARK: - Search by Category
    
    func searchPlacesByCategory(category: String, center: CLLocationCoordinate2D, radiusInMeters: Double, completion: @escaping (Result<[MKMapItem], Error>) -> Void) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category
        
        // Create region based on center and radius
        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radiusInMeters * 2,
            longitudinalMeters: radiusInMeters * 2
        )
        request.region = region
        
        // Set point of interest filter based on category
        if #available(iOS 13.0, *) {
            request.pointOfInterestFilter = getPointOfInterestFilter(for: category)
        }
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let error = error {
                print("❌ AppleMapsService - Search error: \(error)")
                completion(.failure(error))
            } else if let mapItems = response?.mapItems {
                print("✅ AppleMapsService - Found \(mapItems.count) items for category: \(category)")
                completion(.success(mapItems))
            } else {
                print("⚠️ AppleMapsService - No results found")
                completion(.success([]))
            }
        }
    }
    
    // MARK: - Autocomplete Search
    
    func autocompletePlaces(query: String, region: MKCoordinateRegion? = nil, completion: @escaping (Result<[MKLocalSearchCompletion], Error>) -> Void) {
        let completer = MKLocalSearchCompleter()
        completer.resultTypes = [.address, .pointOfInterest]
        
        if let region = region {
            completer.region = region
        }
        
        // Create a temporary delegate to handle results
        let delegate = AppleMapsSearchCompleterDelegate { results, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(results))
            }
        }
        
        completer.delegate = delegate
        completer.queryFragment = query
        
        // Keep delegate alive for the callback
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            _ = delegate
        }
    }
    
    // MARK: - Place Details
    
    func fetchPlaceDetails(mapItem: MKMapItem) -> PlaceDetails {
        let placemark = mapItem.placemark
        
        // Extract address components
        let address = [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode,
            placemark.country
        ].compactMap { $0 }.joined(separator: ", ")
        
        // Map POI category to our PlaceCategory
        let category = mapPointOfInterestCategoryToPlaceCategory(mapItem.pointOfInterestCategory)
        
        return PlaceDetails(
            name: mapItem.name ?? "",
            address: address,
            coordinate: placemark.coordinate,
            phoneNumber: mapItem.phoneNumber,
            website: mapItem.url?.absoluteString,
            category: category,
            poiCategory: mapItem.pointOfInterestCategory
        )
    }
    
    // MARK: - Helper Methods
    
    @available(iOS 13.0, *)
    private func getPointOfInterestFilter(for category: String) -> MKPointOfInterestFilter? {
        let categoryLower = category.lowercased()
        
        if categoryLower.contains("restaurant") || categoryLower.contains("food") {
            return MKPointOfInterestFilter(including: [.restaurant, .foodMarket, .bakery])
        } else if categoryLower.contains("cafe") || categoryLower.contains("coffee") {
            return MKPointOfInterestFilter(including: [.cafe])
        } else if categoryLower.contains("bar") || categoryLower.contains("nightlife") {
            return MKPointOfInterestFilter(including: [.nightlife, .brewery, .winery])
        } else if categoryLower.contains("hotel") || categoryLower.contains("lodging") {
            return MKPointOfInterestFilter(including: [.hotel])
        } else if categoryLower.contains("shopping") || categoryLower.contains("store") {
            return MKPointOfInterestFilter(including: [.store])
        } else if categoryLower.contains("gas") || categoryLower.contains("fuel") {
            return MKPointOfInterestFilter(including: [.gasStation])
        } else if categoryLower.contains("park") || categoryLower.contains("outdoor") {
            return MKPointOfInterestFilter(including: [.park, .nationalPark])
        } else if categoryLower.contains("museum") || categoryLower.contains("attraction") {
            return MKPointOfInterestFilter(including: [.museum, .theater, .movieTheater])
        } else if categoryLower.contains("fitness") || categoryLower.contains("gym") {
            return MKPointOfInterestFilter(including: [.fitnessCenter])
        } else if categoryLower.contains("hospital") || categoryLower.contains("medical") {
            return MKPointOfInterestFilter(including: [.hospital])
        } else if categoryLower.contains("pharmacy") {
            return MKPointOfInterestFilter(including: [.pharmacy])
        } else if categoryLower.contains("bank") || categoryLower.contains("atm") {
            return MKPointOfInterestFilter(including: [.bank, .atm])
        } else {
            // Return nil to search all categories
            return nil
        }
    }
    
    func mapPointOfInterestCategoryToPlaceCategory(_ poiCategory: MKPointOfInterestCategory?) -> PlaceCategory {
        guard let poiCategory = poiCategory else { return .other }
        
        switch poiCategory {
        case .restaurant: return .restaurant
        case .cafe: return .cafe
        case .nightlife, .brewery, .winery: return .bar
        case .hotel: return .hotel
        case .store: return .retail
        case .hospital, .pharmacy: return .healthcare
        case .fitnessCenter: return .fitness
        case .school, .university: return .education
        case .park, .nationalPark, .campground: return .outdoor
        case .gasStation, .evCharger, .publicTransport: return .transport
        case .bank, .atm: return .finance
        case .movieTheater, .theater, .museum, .stadium: return .entertainment
        case .beach, .amusementPark, .zoo, .aquarium: return .attraction
        default:
            // iOS 18 specific categories
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
    
    func getCategoryDescription(for poiCategory: MKPointOfInterestCategory?) -> String {
        guard let poiCategory = poiCategory else { return "" }
        
        switch poiCategory {
        case .restaurant: return "Restaurant serving various cuisines"
        case .cafe: return "Coffee shop and cafe"
        case .nightlife: return "Nightlife and entertainment venue"
        case .brewery: return "Local brewery and taproom"
        case .winery: return "Winery and tasting room"
        case .hotel: return "Hotel and lodging"
        case .store: return "Retail store and shopping"
        case .hospital: return "Medical facility and hospital"
        case .pharmacy: return "Pharmacy and drugstore"
        case .fitnessCenter: return "Fitness center and gym"
        case .school: return "Educational institution"
        case .university: return "University or college campus"
        case .park: return "Public park and recreation area"
        case .nationalPark: return "National park and protected area"
        case .campground: return "Campground and outdoor recreation"
        case .gasStation: return "Gas station and fuel"
        case .evCharger: return "Electric vehicle charging station"
        case .publicTransport: return "Public transportation hub"
        case .bank: return "Banking and financial services"
        case .atm: return "ATM and cash services"
        case .movieTheater: return "Movie theater and cinema"
        case .theater: return "Theater and performing arts"
        case .museum: return "Museum and cultural institution"
        case .stadium: return "Sports stadium and arena"
        case .beach: return "Beach and waterfront recreation"
        case .amusementPark: return "Amusement park and attractions"
        case .zoo: return "Zoo and wildlife park"
        case .aquarium: return "Aquarium and marine life"
        default:
            // iOS 18 specific categories
            if #available(iOS 18.0, *) {
                switch poiCategory {
                case .miniGolf: return "Mini golf recreation"
                case .castle, .landmark: return "Historical landmark or attraction"
                default: return "Local business or point of interest"
                }
            } else {
                return "Local business or point of interest"
            }
        }
    }
}

// MARK: - Supporting Types

struct PlaceDetails {
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let phoneNumber: String?
    let website: String?
    let category: PlaceCategory
    let poiCategory: MKPointOfInterestCategory?
}

// MARK: - Search Completer Delegate

private class AppleMapsSearchCompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
    private let completion: ([MKLocalSearchCompletion], Error?) -> Void
    
    init(completion: @escaping ([MKLocalSearchCompletion], Error?) -> Void) {
        self.completion = completion
        super.init()
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completion(completer.results, nil)
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completion([], error)
    }
}