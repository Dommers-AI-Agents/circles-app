import SwiftUI
import Combine
import MapKit

class PlaceManager: ObservableObject {
    static let shared = PlaceManager()
    
    @Published var places: [Place] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var selectedPlace: Place?
    
    private let placeService = PlaceService.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    func addPlace(to circle: Circle, name: String, description: String?, address: String, category: PlaceCategory) async throws -> Place {
        try await withCheckedThrowingContinuation { continuation in
            placeService.createPlace(
                name: name,
                description: description,
                address: address,
                category: category,
                circleId: circle.id
            ) { result in
                switch result {
                case .success(let addedPlace):
                    continuation.resume(returning: addedPlace)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func updatePlace(_ place: Place, name: String, description: String?, notes: String?, privacy: PlacePrivacy) async throws -> Place {
        try await withCheckedThrowingContinuation { continuation in
            placeService.updatePlace(
                id: place.id,
                name: name,
                description: description,
                privacy: privacy
            ) { result in
                switch result {
                case .success(let updatedPlace):
                    continuation.resume(returning: updatedPlace)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func deletePlace(_ place: Place) async throws {
        try await withCheckedThrowingContinuation { continuation in
            placeService.deletePlace(id: place.id) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func fetchPlaces(for circleId: String) async throws -> [Place] {
        try await withCheckedThrowingContinuation { continuation in
            placeService.fetchPlacesByCircleId(circleId: circleId) { result in
                switch result {
                case .success(let places):
                    continuation.resume(returning: places)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func sharePlace(_ place: Place) -> [Any] {
        var shareText = "Check out \(place.name)"
        
        if let description = place.description {
            shareText += "\n\n\(description)"
        }
        
        shareText += "\n\n📍 \(place.address)"
        
        if let website = place.website, !website.isEmpty {
            shareText += "\n🌐 \(website)"
        }
        
        if let phone = place.phone, !phone.isEmpty {
            shareText += "\n📞 \(phone)"
        }
        
        shareText += "\n\n🔗 Shared from Circles App"
        
        return [shareText]
    }
    
    func searchPlaces(query: String, region: MKCoordinateRegion) async throws -> [MKLocalSearchCompletion] {
        let searchCompleter = MKLocalSearchCompleter()
        searchCompleter.region = region
        searchCompleter.resultTypes = [.address, .pointOfInterest]
        
        return try await withCheckedThrowingContinuation { continuation in
            searchCompleter.queryFragment = query
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                continuation.resume(returning: searchCompleter.results)
            }
        }
    }
    
    func getPlaceDetails(for completion: MKLocalSearchCompletion) async throws -> MKMapItem {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        
        return try await withCheckedThrowingContinuation { continuation in
            search.start { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let mapItem = response?.mapItems.first {
                    continuation.resume(returning: mapItem)
                } else {
                    continuation.resume(throwing: NSError(domain: "PlaceManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "No results found"]))
                }
            }
        }
    }
}