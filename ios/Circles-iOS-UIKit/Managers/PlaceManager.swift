import SwiftUI
import Combine
import MapKit
import GooglePlaces

class PlaceManager: ObservableObject {
    static let shared = PlaceManager()
    
    @Published var places: [Place] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var selectedPlace: Place?
    
    private let placeService = PlaceService.shared
    private let googlePlacesService = GooglePlacesService.shared
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
    
    func updatePlaceComprehensive(
        _ place: Place,
        name: String,
        address: String,
        category: PlaceCategory,
        privacy: PlacePrivacy,
        website: String? = nil,
        phone: String? = nil,
        tags: [String]? = nil,
        privateNotes: String? = nil,
        publicNotes: String? = nil,
        addPhotos: [Data]? = nil,
        removePhotoUrls: [String]? = nil
    ) async throws -> Place {
        try await withCheckedThrowingContinuation { continuation in
            // First update the main place details
            placeService.updatePlace(
                id: place.id,
                name: name,
                description: nil,
                address: address,
                category: category,
                privacy: privacy,
                website: website,
                phone: phone,
                tags: tags,
                addPhotos: addPhotos,
                removePhotoUrls: removePhotoUrls
            ) { result in
                switch result {
                case .success(let updatedPlace):
                    // If notes were provided, update them separately
                    if privateNotes != nil || publicNotes != nil {
                        self.placeService.updatePlace(
                            id: updatedPlace.id,
                            privateNotes: privateNotes,
                            publicNotes: publicNotes
                        ) { notesResult in
                            switch notesResult {
                            case .success(let finalPlace):
                                continuation.resume(returning: finalPlace)
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                    } else {
                        continuation.resume(returning: updatedPlace)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func updatePlaceNotes(_ place: Place, privateNotes: String?, publicNotes: String?) async throws -> Place {
        try await withCheckedThrowingContinuation { continuation in
            placeService.updatePlace(
                id: place.id,
                privateNotes: privateNotes,
                publicNotes: publicNotes
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
        // Create a formatted string with place name prominently displayed
        var shareText = "Check out \(place.name)!"
        
        if let description = place.description, !description.isEmpty {
            shareText += "\n\n\(description)"
        }
        
        // Category
        shareText += "\n\n🏷️ \(place.category.displayName)"
        
        // Address
        shareText += "\n📍 \(place.address)"
        
        // Rating if available
        if let rating = place.rating {
            let stars = String(repeating: "⭐", count: Int(rating.rounded()))
            shareText += "\n\(stars) \(rating)/5.0"
        }
        
        // Contact info if available
        if let phone = place.phone, !phone.isEmpty {
            shareText += "\n📞 \(phone)"
        }
        
        if let website = place.website, !website.isEmpty {
            shareText += "\n🌐 \(website)"
        }
        
        // Add to your places message
        shareText += "\n\n➕ Add this place to your Circles!"
        
        // Deep link to open/add the place in Circles
        let deepLink = "circles://place/\(place.id)"
        shareText += "\n📱 Open in Circles: \(deepLink)"
        
        // App Store link (use TestFlight for now)
        let appStoreLink = "https://testflight.apple.com/join/n1sBRMG3"
        shareText += "\n\nDon't have Circles? Download here: \(appStoreLink)"
        
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
    
    // MARK: - Google Places Integration
    
    func createPlaceWithGoogleData(_ placeData: [String: Any]) async throws -> Place {
        try await withCheckedThrowingContinuation { continuation in
            APIService.shared.request(
                endpoint: "places",
                method: .post,
                body: placeData,
                requiresAuth: true
            ) { (result: Result<PlaceResponse, APIError>) in
                switch result {
                case .success(let response):
                    continuation.resume(returning: response.place)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func uploadPlacePhotos(placeId: String, photos: [UIImage]) async throws {
        // Convert UIImages to Data
        let photosData = photos.compactMap { $0.jpegData(compressionQuality: 0.8) }
        
        guard !photosData.isEmpty else { return }
        
        // Use PlaceService to upload images and get URLs
        let photoUrls = try await withCheckedThrowingContinuation { continuation in
            placeService.uploadMultipleImages(photosData) { result in
                switch result {
                case .success(let urls):
                    continuation.resume(returning: urls)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // Update the place with the photo URLs
        // The updatePlace method expects Data, not URLs, so we pass photosData
        // However, we should consider updating the backend to store the URLs
        try await withCheckedThrowingContinuation { continuation in
            placeService.updatePlace(
                id: placeId,
                addPhotos: photosData
            ) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    func loadGooglePhoto(for metadata: GMSPlacePhotoMetadata) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            googlePlacesService.loadPhoto(from: metadata) { result in
                switch result {
                case .success(let image):
                    continuation.resume(returning: image)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}