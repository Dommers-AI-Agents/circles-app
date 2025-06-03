import Foundation
import CoreLocation

enum PlaceError: Error, LocalizedError {
    case notFound
    case permissionDenied
    case invalidData
    case creationFailed
    case updateFailed
    case deleteFailed
    case invalidLocation
    case locationNotFound
    case networkError(Error)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Place not found"
        case .permissionDenied:
            return "You don't have permission to access this place"
        case .invalidData:
            return "Invalid place data"
        case .creationFailed:
            return "Failed to create place"
        case .updateFailed:
            return "Failed to update place"
        case .deleteFailed:
            return "Failed to delete place"
        case .invalidLocation:
            return "Invalid location coordinates"
        case .locationNotFound:
            return "Couldn't find location for the provided address"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

class PlaceService {
    static let shared = PlaceService()
    
    private let geocoder = CLGeocoder()
    
    private init() {}
    
    // MARK: - Fetch Places
    
    func fetchPlacesByCircleId(circleId: String, completion: @escaping (Result<[Place], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(circleId)/places",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<PlacesResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.places))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    func fetchPlaceById(id: String, completion: @escaping (Result<Place, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "places/\(id)",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<PlaceResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.place))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    func searchPlaces(query: String, category: PlaceCategory? = nil, completion: @escaping (Result<[Place], Error>) -> Void) {
        var queryParams: [String: String] = [
            "q": query
        ]
        
        if let category = category {
            queryParams["category"] = category.rawValue
        }
        
        APIService.shared.request(
            endpoint: "places/search",
            method: .get,
            queryParams: queryParams,
            requiresAuth: true
        ) { [weak self] (result: Result<PlacesResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.places))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    // MARK: - Create, Update, Delete
    
    func createPlace(name: String, description: String?, address: String, category: PlaceCategory, circleId: String, privacy: PlacePrivacy = .followCirclePrivacy, website: String? = nil, phone: String? = nil, tags: [String]? = nil, photos: [Data]? = nil, completion: @escaping (Result<Place, Error>) -> Void) {
        
        // First geocode the address to get coordinates
        geocodeAddress(address) { [weak self] result in
            switch result {
            case .success(let location):
                // Upload photos if provided
                if let photoDataArray = photos, !photoDataArray.isEmpty {
                    self?.uploadMultipleImages(photoDataArray) { photoUrlsResult in
                        switch photoUrlsResult {
                        case .success(let photoUrls):
                            // Create place with location and photo URLs
                            self?.performCreatePlace(
                                name: name,
                                description: description,
                                address: address,
                                location: location,
                                category: category,
                                circleId: circleId,
                                privacy: privacy,
                                website: website,
                                phone: phone,
                                tags: tags,
                                photoUrls: photoUrls,
                                completion: completion
                            )
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                } else {
                    // Create place with location but no photos
                    self?.performCreatePlace(
                        name: name,
                        description: description,
                        address: address,
                        location: location,
                        category: category,
                        circleId: circleId,
                        privacy: privacy,
                        website: website,
                        phone: phone,
                        tags: tags,
                        photoUrls: nil,
                        completion: completion
                    )
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func performCreatePlace(name: String, description: String?, address: String, location: CLLocationCoordinate2D, category: PlaceCategory, circleId: String, privacy: PlacePrivacy, website: String?, phone: String?, tags: [String]?, photoUrls: [String]?, completion: @escaping (Result<Place, Error>) -> Void) {
        
        var body: [String: Any] = [
            "name": name,
            "address": address,
            "location": [
                "type": "Point",
                "coordinates": [location.longitude, location.latitude]
            ],
            "category": category.rawValue,
            "circleId": circleId,
            "privacy": privacy.rawValue
        ]
        
        if let description = description {
            body["description"] = description
        }
        
        if let website = website {
            body["website"] = website
        }
        
        if let phone = phone {
            body["phone"] = phone
        }
        
        if let tags = tags {
            body["tags"] = tags
        }
        
        if let photoUrls = photoUrls, !photoUrls.isEmpty {
            body["photos"] = photoUrls
        }
        
        APIService.shared.request(
            endpoint: "places",
            method: .post,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<PlaceResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.place))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? PlaceError.creationFailed))
            }
        }
    }
    
    func updatePlace(id: String, name: String? = nil, description: String? = nil, address: String? = nil, category: PlaceCategory? = nil, privacy: PlacePrivacy? = nil, website: String? = nil, phone: String? = nil, tags: [String]? = nil, addPhotos: [Data]? = nil, removePhotoUrls: [String]? = nil, completion: @escaping (Result<Place, Error>) -> Void) {
        
        var locationCoordinate: CLLocationCoordinate2D?
        var photosUrls: [String]?
        var geocodeError: Error?
        var uploadError: Error?
        
        let taskGroup = DispatchGroup()
        
        // If address is provided, geocode it
        if let address = address {
            taskGroup.enter()
            geocodeAddress(address) { result in
                switch result {
                case .success(let location):
                    locationCoordinate = location
                case .failure(let error):
                    geocodeError = error
                }
                taskGroup.leave()
            }
        }
        
        // If photos are provided, upload them
        if let photos = addPhotos, !photos.isEmpty {
            taskGroup.enter()
            uploadMultipleImages(photos) { result in
                switch result {
                case .success(let urls):
                    photosUrls = urls
                case .failure(let error):
                    uploadError = error
                }
                taskGroup.leave()
            }
        }
        
        // After all async tasks are done, update the place
        taskGroup.notify(queue: .main) {
            // Check for errors
            if let error = geocodeError {
                completion(.failure(error))
                return
            }
            
            if let error = uploadError {
                completion(.failure(error))
                return
            }
            
            // Start building the update body
            var body: [String: Any] = [:]
            
            if let name = name {
                body["name"] = name
            }
            
            if let description = description {
                body["description"] = description
            }
            
            if let newAddress = address {
                body["address"] = newAddress
                
                // Add location if geocoding was successful
                if let location = locationCoordinate {
                    body["location"] = [
                        "type": "Point",
                        "coordinates": [location.longitude, location.latitude]
                    ]
                }
            }
            
            if let category = category {
                body["category"] = category.rawValue
            }
            
            if let privacy = privacy {
                body["privacy"] = privacy.rawValue
            }
            
            if let website = website {
                body["website"] = website
            }
            
            if let phone = phone {
                body["phone"] = phone
            }
            
            if let tags = tags {
                body["tags"] = tags
            }
            
            // Add new photo URLs if any were uploaded
            if let urls = photosUrls, !urls.isEmpty {
                body["addPhotos"] = urls
            }
            
            // Add URLs of photos to remove
            if let removePhotoUrls = removePhotoUrls, !removePhotoUrls.isEmpty {
                body["removePhotos"] = removePhotoUrls
            }
            
            // Only proceed if there are changes to make
            guard !body.isEmpty else {
                completion(.failure(PlaceError.invalidData))
                return
            }
            
            APIService.shared.request(
                endpoint: "places/\(id)",
                method: .put,
                body: body,
                requiresAuth: true
            ) { [weak self] (result: Result<PlaceResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.place))
                case .failure(let error):
                    let mappedError = self?.mapAPIErrorToPlaceError(error)
                    completion(.failure(mappedError ?? PlaceError.updateFailed))
                }
            }
        }
    }
    
    func deletePlace(id: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "places/\(id)",
            method: .delete,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToPlaceError(error)
                completion(.failure(mappedError ?? PlaceError.deleteFailed))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func geocodeAddress(_ address: String, completion: @escaping (Result<CLLocationCoordinate2D, Error>) -> Void) {
        geocoder.geocodeAddressString(address) { placemarks, error in
            if let error = error {
                completion(.failure(PlaceError.networkError(error)))
                return
            }
            
            guard let placemark = placemarks?.first,
                  let location = placemark.location?.coordinate else {
                completion(.failure(PlaceError.locationNotFound))
                return
            }
            
            completion(.success(location))
        }
    }
    
    private func uploadMultipleImages(_ imagesData: [Data], completion: @escaping (Result<[String], Error>) -> Void) {
        let uploadGroup = DispatchGroup()
        var uploadedUrls: [String] = []
        var uploadError: Error?
        
        for imageData in imagesData {
            uploadGroup.enter()
            
            uploadImage(imageData) { result in
                switch result {
                case .success(let url):
                    uploadedUrls.append(url)
                case .failure(let error):
                    uploadError = error
                }
                
                uploadGroup.leave()
            }
        }
        
        uploadGroup.notify(queue: .main) {
            if let error = uploadError {
                completion(.failure(error))
            } else {
                completion(.success(uploadedUrls))
            }
        }
    }
    
    private func uploadImage(_ imageData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        // In a real app, this would upload the image to a cloud storage service
        // For now, we'll simulate it with a mock URL
        
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            // Generate a mock image URL
            let mockImageUrl = "https://storage.circles-app.com/images/\(UUID().uuidString).jpg"
            completion(.success(mockImageUrl))
        }
    }
    
    // MARK: - Error Mapping
    
    private func mapAPIErrorToPlaceError(_ error: APIError) -> PlaceError {
        switch error {
        case .httpError(let statusCode, _):
            switch statusCode {
            case 403:
                return .permissionDenied
            case 404:
                return .notFound
            case 400:
                return .invalidData
            default:
                return .unknown
            }
            
        case .unauthorized:
            return .permissionDenied
            
        case .noInternet, .requestFailed, .invalidURL, .invalidResponse, .decodingFailed:
            return .networkError(error)
            
        case .serverError, .unknown:
            return .unknown
        }
    }
}

// MARK: - Response Types

struct PlacesResponse: Decodable {
    let success: Bool
    let places: [Place]
}

struct PlaceResponse: Decodable {
    let success: Bool
    let place: Place
}