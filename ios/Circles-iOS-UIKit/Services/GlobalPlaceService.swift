import Foundation
import Combine

class GlobalPlaceService {
    static let shared = GlobalPlaceService()
    private let apiService = APIService.shared
    
    private init() {}
    
    // MARK: - API Endpoints
    
    /// Does this venue already exist in our canonical database? Called
    /// before fetching photos from Google Places so duplicate adds reuse the
    /// canonical record's googlePlaceId + photos instead of re-querying
    /// Google. Returns nil match when the place is new to us.
    func matchKnownPlace(name: String, latitude: Double?, longitude: Double?, address: String?, completion: @escaping (Result<KnownPlaceMatch?, Error>) -> Void) {
        var params = "name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)"
        if let latitude = latitude, let longitude = longitude {
            params += "&lat=\(latitude)&lng=\(longitude)"
        }
        if let address = address,
           let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            params += "&address=\(encoded)"
        }

        apiService.request(
            endpoint: "places/global/match?\(params)",
            method: .get,
            queryParams: nil,
            body: nil,
            headers: nil,
            requiresAuth: true
        ) { (result: Result<KnownPlaceMatchResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.match))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Get global place by ID with all public content
    /// - Parameters:
    ///   - placeId: The global place ID
    ///   - completion: Completion handler with GlobalPlaceResponse
    func getGlobalPlace(id placeId: String, completion: @escaping (Result<GlobalPlaceResponse, Error>) -> Void) {
        let endpoint = "places/global/\(placeId)"
        print("🔍 [GlobalPlaceService] Requesting GlobalPlace for ID: \(placeId)")
        print("📍 [GlobalPlaceService] API endpoint: \(endpoint)")
        
        apiService.request(
            endpoint: endpoint,
            method: .get,
            queryParams: nil,
            body: nil,
            headers: nil,
            requiresAuth: true
        ) { (result: Result<GlobalPlaceDetailResponse, APIError>) in
            switch result {
            case .success(let response):
                print("✅ [GlobalPlaceService] API call successful")
                if response.success {
                    let globalPlace = response.data.globalPlace
                    print("📍 [GlobalPlaceService] GlobalPlace found: \(globalPlace.name)")
                    print("📷 [GlobalPlaceService] Photos count: \(globalPlace.photos?.count ?? 0)")
                    print("📝 [GlobalPlaceService] PublicReviews count: \(globalPlace.publicReviews?.count ?? 0)")
                    
                    if let photos = globalPlace.photos, !photos.isEmpty {
                        let firstPhoto = photos[0]
                        print("📸 [GlobalPlaceService] First photo attribution: '\(firstPhoto.uploadedByName ?? "Unknown")'")
                    }
                    
                    if let reviews = globalPlace.publicReviews, !reviews.isEmpty {
                        let firstReview = reviews[0]
                        print("💬 [GlobalPlaceService] First review text: '\(firstReview.text)'")
                        print("👍 [GlobalPlaceService] First review likes: \(firstReview.likesCount)")
                        print("⭐ [GlobalPlaceService] First review rating: \(firstReview.rating ?? -1)")
                    }
                    
                    print("📊 [GlobalPlaceService] UserContributions - Reviews: \(globalPlace.userContributions.totalReviews), Photos: \(globalPlace.userContributions.totalPhotos), Videos: \(globalPlace.userContributions.totalVideos)")
                    completion(.success(response.data))
                } else {
                    print("❌ [GlobalPlaceService] API returned success=false")
                    completion(.failure(APIError.serverError))
                }
            case .failure(let error):
                print("❌ [GlobalPlaceService] API call failed: \(error)")
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
        
        let endpoint = "places/global/search"
        
        apiService.request(
            endpoint: endpoint,
            method: .get,
            queryParams: queryParams,
            body: nil,
            headers: nil,
            requiresAuth: true
        ) { (result: Result<GlobalPlaceSearchResponse, APIError>) in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.data))
                } else {
                    completion(.failure(APIError.serverError))
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
        let endpoint = "places/global"
        
        apiService.request(
            endpoint: endpoint,
            method: .post,
            queryParams: nil,
            body: placeData,
            headers: nil,
            requiresAuth: true
        ) { (result: Result<CreateGlobalPlaceResponse, APIError>) in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success((place: response.data, created: response.created)))
                } else {
                    completion(.failure(APIError.serverError))
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
        let endpoint = "places/global/\(placeId)/relations"
        
        let requestData: [String: Any] = [
            "circleId": circleId,
            "privateNotes": privateNotes as Any,
            "tags": tags as Any,
            "privacy": privacy.rawValue
        ]
        
        apiService.request(
            endpoint: endpoint,
            method: .post,
            queryParams: nil,
            body: requestData,
            headers: nil,
            requiresAuth: true
        ) { (result: Result<StandardResponse<UserPlaceRelation>, APIError>) in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.data))
                } else {
                    completion(.failure(APIError.serverError))
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
        let endpoint = "places/global/\(placeId)/reviews"
        
        let requestData: [String: Any] = [
            "text": text,
            "rating": rating as Any,
            "photos": photos as Any
        ]
        
        apiService.request(
            endpoint: endpoint,
            method: .post,
            queryParams: nil,
            body: requestData,
            headers: nil,
            requiresAuth: true
        ) { (result: Result<StandardResponse<PublicReview>, APIError>) in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.data))
                } else {
                    completion(.failure(APIError.serverError))
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
        completion: @escaping (Result<AttributedPhoto, Error>) -> Void
    ) {
        let endpoint = "places/global/\(placeId)/media"
        
        let requestData: [String: Any] = [
            "mediaType": mediaType,
            "mediaUrl": mediaUrl,
            "thumbnailUrl": thumbnailUrl as Any,
            "title": title as Any,
            "description": description as Any
        ]
        
        // For media upload, we'll return a generic success response
        // since the specific media type varies
        apiService.request(
            endpoint: endpoint,
            method: .post,
            queryParams: nil,
            body: requestData,
            headers: nil,
            requiresAuth: true
        ) { (result: Result<StandardResponse<AttributedPhoto>, APIError>) in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.data))
                } else {
                    completion(.failure(APIError.serverError))
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
        let endpoint = "places/global/\(placeId)/user-relation"
        
        apiService.request(
            endpoint: endpoint,
            method: .get,
            queryParams: nil,
            body: nil,
            headers: nil,
            requiresAuth: true
        ) { (result: Result<StandardResponse<[UserPlaceRelation]>, APIError>) in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.data))
                } else {
                    completion(.failure(APIError.serverError))
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
        let endpoint = "places/global/\(placeId)/relations/\(relationId)"
        
        apiService.request(
            endpoint: endpoint,
            method: .put,
            queryParams: nil,
            body: updates,
            headers: nil,
            requiresAuth: true
        ) { (result: Result<StandardResponse<UserPlaceRelation>, APIError>) in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.data))
                } else {
                    completion(.failure(APIError.serverError))
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
        
        completion(.failure(APIError.serverError))
    }
    
    // MARK: - User Uploads
    
    /// Get all images uploaded by a user to Global Places
    /// - Parameters:
    ///   - userId: User ID (nil for current user)
    ///   - limit: Maximum number of results (default: 20)
    ///   - offset: Pagination offset (default: 0)
    ///   - completion: Completion handler with UserUploadsResponse
    func getUserUploads(
        userId: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        completion: @escaping (Result<UserUploadsResponse, Error>) -> Void
    ) {
        // Use current user's ID if not specified
        let targetUserId = userId ?? AuthService.shared.getUserId() ?? ""
        
        let endpoint = "users/\(targetUserId)/uploads"
        let queryParams = [
            "limit": "\(limit)",
            "offset": "\(offset)"
        ]
        
        print("🔍 [GlobalPlaceService] Requesting user uploads for ID: \(targetUserId)")
        print("📍 [GlobalPlaceService] API endpoint: \(endpoint)")
        print("📊 [GlobalPlaceService] Query params: limit=\(limit), offset=\(offset)")
        
        apiService.request(
            endpoint: endpoint,
            method: .get,
            queryParams: queryParams,
            body: nil,
            headers: nil,
            requiresAuth: true
        ) { (result: Result<UserUploadsResponse, APIError>) in
            switch result {
            case .success(let response):
                print("✅ [GlobalPlaceService] User uploads API call successful")
                if response.success {
                    print("📷 [GlobalPlaceService] Found \(response.data.count) uploads (total: \(response.total))")
                    completion(.success(response))
                } else {
                    print("❌ [GlobalPlaceService] API returned success=false")
                    completion(.failure(APIError.serverError))
                }
            case .failure(let error):
                print("❌ [GlobalPlaceService] User uploads API call failed: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    /// Delete a user's uploaded photo from a Global Place
    /// - Parameters:
    ///   - upload: The UserUploadedPhoto to delete
    ///   - completion: Completion handler
    func deleteUpload(
        _ upload: UserUploadedPhoto,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let endpoint = "places/global/\(upload.placeId)/media/\(upload.id)"
        
        print("🗑️ [GlobalPlaceService] Deleting upload: \(upload.id) from place: \(upload.placeId)")
        
        apiService.request(
            endpoint: endpoint,
            method: .delete,
            queryParams: nil,
            body: nil,
            headers: nil,
            requiresAuth: true
        ) { (result: Result<StandardResponse<String>, APIError>) in
            switch result {
            case .success(let response):
                if response.success {
                    print("✅ [GlobalPlaceService] Successfully deleted upload: \(upload.id)")
                    completion(.success(()))
                } else {
                    print("❌ [GlobalPlaceService] Delete failed - API returned success=false")
                    completion(.failure(APIError.serverError))
                }
            case .failure(let error):
                print("❌ [GlobalPlaceService] Delete upload failed: \(error)")
                completion(.failure(error))
            }
        }
    }

    /// Like or unlike a photo on a Global Place. Accepts a legacy place id or a
    /// global place id (the backend resolves both). Idempotent server-side.
    func setPhotoLiked(
        placeId: String,
        photoId: String,
        liked: Bool,
        completion: @escaping (Result<Int?, Error>) -> Void
    ) {
        let endpoint = "places/global/\(placeId)/media/\(photoId)/like"

        apiService.request(
            endpoint: endpoint,
            method: liked ? .post : .delete,
            queryParams: nil,
            body: liked ? [:] : nil,
            headers: nil,
            requiresAuth: true
        ) { (result: Result<PhotoLikeResponse, APIError>) in
            switch result {
            case .success(let response):
                if response.success {
                    completion(.success(response.likesCount))
                } else {
                    completion(.failure(APIError.serverError))
                }
            case .failure(let error):
                print("❌ [GlobalPlaceService] setPhotoLiked(\(liked)) failed: \(error)")
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Photo Like Response
struct PhotoLikeResponse: Codable {
    let success: Bool
    let likesCount: Int?
}

// MARK: - Standard Response Model
struct StandardResponse<T: Codable>: Codable {
    let success: Bool
    let data: T
    let message: String?
}