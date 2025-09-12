import Foundation
import Combine

class GlobalPlaceService {
    static let shared = GlobalPlaceService()
    private let apiService = APIService.shared
    
    private init() {}
    
    // MARK: - API Endpoints
    
    /// Get global place by ID with all public content
    /// - Parameters:
    ///   - placeId: The global place ID
    ///   - completion: Completion handler with GlobalPlaceResponse
    func getGlobalPlace(id placeId: String, completion: @escaping (Result<GlobalPlaceResponse, Error>) -> Void) {
        let endpoint = "/api/places/global/\(placeId)"
        
        apiService.request(
            endpoint: endpoint,
            method: .GET,
            responseType: GlobalPlaceDetailResponse.self
        ) { result in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.data))
                } else {
                    completion(.failure(APIError.serverError("Failed to get global place")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Search global places
    /// - Parameters:
    ///   - query: Search query string
    ///   - category: Filter by category (optional)
    ///   - location: User's location for distance sorting (optional)
    ///   - radius: Search radius in km (default 50)
    ///   - limit: Number of results (default 20)
    ///   - completion: Completion handler with array of GlobalPlace
    func searchGlobalPlaces(
        query: String? = nil,
        category: String? = nil,
        location: (lat: Double, lng: Double)? = nil,
        radius: Double = 50,
        limit: Int = 20,
        completion: @escaping (Result<[GlobalPlace], Error>) -> Void
    ) {
        var queryParams: [String: String] = [
            "limit": "\(limit)",
            "radius": "\(radius)"
        ]
        
        if let query = query, !query.isEmpty {
            queryParams["query"] = query
        }
        
        if let category = category {
            queryParams["category"] = category
        }
        
        if let location = location {
            queryParams["lat"] = "\(location.lat)"
            queryParams["lng"] = "\(location.lng)"
        }
        
        let endpoint = "/api/places/global/search"
        
        apiService.requestWithQuery(
            endpoint: endpoint,
            method: .GET,
            queryParams: queryParams,
            responseType: GlobalPlaceSearchResponse.self
        ) { result in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.data))
                } else {
                    completion(.failure(APIError.serverError("Search failed")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Create or get global place
    /// - Parameters:
    ///   - placeData: Place data to create
    ///   - completion: Completion handler with created/existing GlobalPlace
    func createOrGetGlobalPlace(
        placeData: [String: Any],
        completion: @escaping (Result<(place: GlobalPlace, created: Bool), Error>) -> Void
    ) {
        let endpoint = "/api/places/global"
        
        apiService.request(
            endpoint: endpoint,
            method: .POST,
            body: placeData,
            responseType: CreateGlobalPlaceResponse.self
        ) { result in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success((place: response.data, created: response.created)))
                } else {
                    completion(.failure(APIError.serverError(response.message)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Add place to user's circle (create user-place relationship)
    /// - Parameters:
    ///   - placeId: Global place ID
    ///   - circleId: Circle to add place to
    ///   - privateNotes: User's private notes (optional)
    ///   - tags: User's tags (optional)
    ///   - privacy: Privacy setting
    ///   - completion: Completion handler with UserPlaceRelation
    func addPlaceToCircle(
        placeId: String,
        circleId: String,
        privateNotes: String? = nil,
        tags: [String]? = nil,
        privacy: PlacePrivacy = .followCirclePrivacy,
        completion: @escaping (Result<UserPlaceRelation, Error>) -> Void
    ) {
        let endpoint = "/api/places/global/\(placeId)/relations"
        
        let requestData: [String: Any] = [
            "circleId": circleId,
            "privateNotes": privateNotes as Any,
            "tags": tags as Any,
            "privacy": privacy.rawValue
        ]
        
        apiService.request(
            endpoint: endpoint,
            method: .POST,
            body: requestData,
            responseType: StandardResponse<UserPlaceRelation>.self
        ) { result in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.data))
                } else {
                    completion(.failure(APIError.serverError(response.message ?? "Failed to add place to circle")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Add public review to global place
    /// - Parameters:
    ///   - placeId: Global place ID
    ///   - text: Review text
    ///   - rating: Star rating (1-5, optional)
    ///   - photos: Photo URLs (optional)
    ///   - completion: Completion handler with created review
    func addPublicReview(
        placeId: String,
        text: String,
        rating: Double? = nil,
        photos: [String]? = nil,
        completion: @escaping (Result<PublicReview, Error>) -> Void
    ) {
        let endpoint = "/api/places/global/\(placeId)/reviews"
        
        let requestData: [String: Any] = [
            "text": text,
            "rating": rating as Any,
            "photos": photos as Any
        ]
        
        apiService.request(
            endpoint: endpoint,
            method: .POST,
            body: requestData,
            responseType: StandardResponse<PublicReview>.self
        ) { result in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.data))
                } else {
                    completion(.failure(APIError.serverError(response.message ?? "Failed to add review")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Upload media to global place
    /// - Parameters:
    ///   - placeId: Global place ID
    ///   - mediaType: "photo" or "video"
    ///   - mediaUrl: URL of uploaded media
    ///   - thumbnailUrl: Thumbnail URL for videos (optional)
    ///   - title: Media title (optional)
    ///   - description: Media description (optional)
    ///   - completion: Completion handler
    func uploadPlaceMedia(
        placeId: String,
        mediaType: String,
        mediaUrl: String,
        thumbnailUrl: String? = nil,
        title: String? = nil,
        description: String? = nil,
        completion: @escaping (Result<Any, Error>) -> Void
    ) {
        let endpoint = "/api/places/global/\(placeId)/media"
        
        let requestData: [String: Any] = [
            "mediaType": mediaType,
            "mediaUrl": mediaUrl,
            "thumbnailUrl": thumbnailUrl as Any,
            "title": title as Any,
            "description": description as Any
        ]
        
        apiService.request(
            endpoint: endpoint,
            method: .POST,
            body: requestData,
            responseType: StandardResponse<[String: Any]>.self
        ) { result in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.data))
                } else {
                    completion(.failure(APIError.serverError(response.message ?? "Failed to upload media")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Get user's relationships to a place
    /// - Parameters:
    ///   - placeId: Global place ID
    ///   - completion: Completion handler with array of UserPlaceRelation
    func getUserPlaceRelations(
        placeId: String,
        completion: @escaping (Result<[UserPlaceRelation], Error>) -> Void
    ) {
        let endpoint = "/api/places/global/\(placeId)/user-relation"
        
        apiService.request(
            endpoint: endpoint,
            method: .GET,
            responseType: StandardResponse<[UserPlaceRelation]>.self
        ) { result in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.data))
                } else {
                    completion(.failure(APIError.serverError("Failed to get user relations")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Update user-place relationship
    /// - Parameters:
    ///   - placeId: Global place ID
    ///   - relationId: User-place relation ID
    ///   - updates: Fields to update
    ///   - completion: Completion handler with updated relation
    func updateUserPlaceRelation(
        placeId: String,
        relationId: String,
        updates: [String: Any],
        completion: @escaping (Result<UserPlaceRelation, Error>) -> Void
    ) {
        let endpoint = "/api/places/global/\(placeId)/relations/\(relationId)"
        
        apiService.request(
            endpoint: endpoint,
            method: .PUT,
            body: updates,
            responseType: StandardResponse<UserPlaceRelation>.self
        ) { result in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.data))
                } else {
                    completion(.failure(APIError.serverError(response.message ?? "Failed to update relation")))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Convenience Methods
extension GlobalPlaceService {
    
    /// Convert legacy Place to GlobalPlace request format
    /// - Parameter place: Legacy Place object
    /// - Returns: Dictionary suitable for createOrGetGlobalPlace
    func convertLegacyPlaceToGlobalRequest(place: Place) -> [String: Any] {
        var requestData: [String: Any] = [
            "name": place.name,
            "address": place.address,
            "category": place.category.rawValue
        ]
        
        if let description = place.description {
            requestData["description"] = description
        }
        
        if let location = place.location {
            requestData["location"] = [
                "type": "Point",
                "coordinates": location.coordinates
            ]
        }
        
        if let subcategory = place.subcategory {
            requestData["subcategory"] = subcategory
        }
        
        if let googlePlaceId = place.googlePlaceId {
            requestData["googlePlaceId"] = googlePlaceId
        }
        
        if let website = place.website {
            requestData["website"] = website
        }
        
        if let phone = place.phone {
            requestData["phone"] = phone
        }
        
        if let rating = place.rating {
            requestData["rating"] = rating
        }
        
        if let userRatingsTotal = place.userRatingsTotal {
            requestData["userRatingsTotal"] = userRatingsTotal
        }
        
        if let priceLevel = place.priceLevel {
            requestData["priceLevel"] = priceLevel.rawValue
        }
        
        if let photos = place.photos {
            requestData["photos"] = photos
        }
        
        if let videos = place.videos {
            requestData["videos"] = videos
        }
        
        if let notes = place.notes {
            requestData["notes"] = notes
        }
        
        return requestData
    }
    
    /// Get places for a circle using global place system
    /// - Parameters:
    ///   - circleId: Circle ID
    ///   - completion: Completion handler with array of Places (converted from global)
    func getCirclePlacesAsLegacy(
        circleId: String,
        completion: @escaping (Result<[Place], Error>) -> Void
    ) {
        // This would require a new API endpoint that returns circle places in global format
        // For now, we'll use a placeholder that calls the transition service
        
        // TODO: Implement circle places endpoint that uses global places
        // For backwards compatibility, we can continue using the existing endpoint
        // and gradually migrate circles to use global places
        
        completion(.failure(APIError.serverError("Not yet implemented - use legacy PlaceService")))
    }
}

// MARK: - Standard Response Model
struct StandardResponse<T: Codable>: Codable {
    let success: Bool
    let data: T
    let message: String?
}