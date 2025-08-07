import Foundation

// Notification for circle deletion
extension Notification.Name {
    static let circleDeleted = Notification.Name("circleDeleted")
}

enum CircleError: Error, LocalizedError {
    case notFound
    case permissionDenied
    case invalidData
    case creationFailed
    case updateFailed
    case deleteFailed
    case fetchFailed
    case networkError(Error)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Circle not found"
        case .permissionDenied:
            return "You don't have permission to access this circle"
        case .invalidData:
            return "Invalid circle data"
        case .creationFailed:
            return "Failed to create circle"
        case .updateFailed:
            return "Failed to update circle"
        case .deleteFailed:
            return "Failed to delete circle"
        case .fetchFailed:
            return "Failed to fetch circles"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

class CircleService {
    static let shared = CircleService()
    
    private init() {}
    
    // MARK: - Helper Methods
    
    /// Helper function to create a type-safe completion handler for API requests
    private func createAPICompletion<T>(_ completion: @escaping (Result<T, Error>) -> Void) -> (Result<T, APIError>) -> Void {
        return { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    // MARK: - Fetch Circles
    
    func fetchUserCircles(completion: @escaping (Result<[Circle], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/me",
            method: .get,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CirclesResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response.circles))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError))
            }
        })
    }
    
    func fetchUserCircles(userId: String, completion: @escaping (Result<[Circle], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/\(userId)/circles",
            method: .get,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CirclesResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response.circles))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError))
            }
        })
    }
    
    func fetchCircleById(id: String, completion: @escaping (Result<Circle, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(id)",
            method: .get,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CircleResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response.circle))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError))
            }
        })
    }
    
    func fetchCircleByIdPublic(id: String, completion: @escaping (Result<Circle, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(id)/public",
            method: .get,
            requiresAuth: false,
            completion: { [weak self] (result: Result<CircleResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response.circle))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError))
            }
        })
    }
    
    func fetchPublicCircles(page: Int = 1, limit: Int = 20, category: CircleCategory? = nil, completion: @escaping (Result<[Circle], Error>) -> Void) {
        var queryParams: [String: String] = [
            "page": "\(page)",
            "limit": "\(limit)"
        ]
        
        if let category = category {
            queryParams["category"] = category.rawValue
        }
        
        APIService.shared.request(
            endpoint: "circles/public",
            method: .get,
            queryParams: queryParams,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CirclesResponse, APIError>) in
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    completion(.success(response.circles))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func searchCircles(query: String, category: CircleCategory? = nil, completion: @escaping (Result<[Circle], Error>) -> Void) {
        var queryParams: [String: String] = [
            "q": query
        ]
        
        if let category = category {
            queryParams["category"] = category.rawValue
        }
        
        APIService.shared.request(
            endpoint: "circles/search",
            method: .get,
            queryParams: queryParams,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CirclesResponse, APIError>) in
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    completion(.success(response.circles))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    // MARK: - Create, Update, Delete
    
    func createCircle(name: String, description: String?, privacy: PrivacyLevel, category: CircleCategory, customCategoryId: String? = nil, location: String? = nil, tags: [String]? = nil, coverImage: Data? = nil, completion: @escaping (Result<Circle, Error>) -> Void) {
        
        // First check if we need to upload an image
        if let imageData = coverImage {
            uploadImage(imageData) { [weak self] result in
                switch result {
                case .success(let imageUrl):
                    // Now create the circle with the image URL
                    self?.performCreateCircle(name: name, description: description, privacy: privacy, category: category, customCategoryId: customCategoryId, location: location, tags: tags, coverImageUrl: imageUrl, completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            // Create circle without image
            performCreateCircle(name: name, description: description, privacy: privacy, category: category, customCategoryId: customCategoryId, location: location, tags: tags, coverImageUrl: nil, completion: completion)
        }
    }
    
    private func performCreateCircle(name: String, description: String?, privacy: PrivacyLevel, category: CircleCategory, customCategoryId: String?, location: String?, tags: [String]?, coverImageUrl: String?, completion: @escaping (Result<Circle, Error>) -> Void) {
        
        var body: [String: Any] = [
            "name": name,
            "privacy": privacy.rawValue,
            "category": category.rawValue
        ]
        
        if let description = description {
            body["description"] = description
        }
        
        if let location = location {
            body["location"] = location
        }
        
        if let tags = tags {
            body["tags"] = tags
        }
        
        if let coverImageUrl = coverImageUrl {
            body["coverImage"] = coverImageUrl
        }
        
        if let customCategoryId = customCategoryId {
            body["customCategoryId"] = customCategoryId
        }
        
        APIService.shared.request(
            endpoint: "circles",
            method: .post,
            body: body,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CircleResponse, APIError>) in
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    completion(.success(response.circle))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func updateCircle(id: String, name: String? = nil, description: String? = nil, privacy: PrivacyLevel? = nil, category: CircleCategory? = nil, customCategoryId: String? = nil, location: String? = nil, tags: [String]? = nil, coverImage: Data? = nil, completion: @escaping (Result<Circle, Error>) -> Void) {
        
        // First check if we need to upload an image
        if let imageData = coverImage {
            uploadImage(imageData) { [weak self] result in
                switch result {
                case .success(let imageUrl):
                    // Now update the circle with the image URL
                    self?.performUpdateCircle(id: id, name: name, description: description, privacy: privacy, category: category, customCategoryId: customCategoryId, location: location, tags: tags, coverImageUrl: imageUrl, completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            // Update circle without changing image
            performUpdateCircle(id: id, name: name, description: description, privacy: privacy, category: category, customCategoryId: customCategoryId, location: location, tags: tags, coverImageUrl: nil, completion: completion)
        }
    }
    
    private func performUpdateCircle(id: String, name: String?, description: String?, privacy: PrivacyLevel?, category: CircleCategory?, customCategoryId: String?, location: String?, tags: [String]?, coverImageUrl: String?, completion: @escaping (Result<Circle, Error>) -> Void) {
        
        var body: [String: Any] = [:]
        
        if let name = name {
            body["name"] = name
        }
        
        if let description = description {
            body["description"] = description
        }
        
        if let privacy = privacy {
            body["privacy"] = privacy.rawValue
        }
        
        if let category = category {
            body["category"] = category.rawValue
        }
        
        if let customCategoryId = customCategoryId {
            body["customCategoryId"] = customCategoryId
        }
        
        if let location = location {
            body["location"] = location
        }
        
        if let tags = tags {
            body["tags"] = tags
        }
        
        if let coverImageUrl = coverImageUrl {
            body["coverImage"] = coverImageUrl
            print("Updating circle with cover image URL: \(coverImageUrl)")
        }
        
        // Only proceed if there are changes to make
        guard !body.isEmpty else {
            completion(.failure(CircleError.invalidData))
            return
        }
        
        print("Updating circle \(id) with body: \(body)")
        
        APIService.shared.request(
            endpoint: "circles/\(id)",
            method: .put,
            body: body,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CircleResponse, APIError>) in
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    print("Circle updated successfully with coverImage: \(response.circle.coverImage ?? "nil")")
                    completion(.success(response.circle))
                case .failure(let error):
                    print("Circle update failed: \(error)")
                    completion(.failure(error))
                }
            }
        )
    }
    
    func deleteCircle(id: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(id)",
            method: .delete,
            requiresAuth: true,
            completion: { [weak self] (result: Result<EmptyResponse, APIError>) in
                switch result {
                case .success(_):
                    // Post notification for circle deletion
                    NotificationCenter.default.post(
                        name: .circleDeleted,
                        object: nil,
                        userInfo: ["circleId": id]
                    )
                    completion(.success(true))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    // MARK: - User Circles
    
    func fetchUserPublicCircles(userId: String, completion: @escaping (Result<[Circle], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/\(userId)/circles",
            method: .get,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CirclesResponse, APIError>) in
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    completion(.success(response.circles))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    // MARK: - Social Functions
    
    func shareCircle(id: String, userIds: [String], completion: @escaping (Result<Bool, Error>) -> Void) {
        let body: [String: Any] = ["userIds": userIds]
        
        APIService.shared.request(
            endpoint: "circles/\(id)/share",
            method: .post,
            body: body,
            requiresAuth: true,
            completion: { [weak self] (result: Result<EmptyResponse, APIError>) in
                guard let self = self else { return }
                
                switch result {
                case .success(_):
                    completion(.success(true))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func followCircle(id: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(id)/follow",
            method: .post,
            requiresAuth: true,
            completion: { [weak self] (result: Result<EmptyResponse, APIError>) in
                guard let self = self else { return }
                
                switch result {
                case .success(_):
                    completion(.success(true))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func unfollowCircle(id: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(id)/unfollow",
            method: .post,
            requiresAuth: true,
            completion: { [weak self] (result: Result<EmptyResponse, APIError>) in
                guard let self = self else { return }
                
                switch result {
                case .success(_):
                    completion(.success(true))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    // MARK: - Helper Methods
    
    private func uploadImage(_ imageData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        // Convert image data to base64
        let base64String = imageData.base64EncodedString()
        
        print("Uploading image - size: \(imageData.count) bytes, base64 length: \(base64String.count)")
        
        let body: [String: Any] = [
            "image": base64String,
            "filename": "circle-image.jpg"
        ]
        
        APIService.shared.request(
            endpoint: "upload/image",
            method: .post,
            body: body,
            requiresAuth: true,
            completion: { [weak self] (result: Result<ImageUploadResponse, APIError>) in
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    print("Image uploaded successfully: \(response.url)")
                    completion(.success(response.url))
                case .failure(let error):
                    print("Image upload failed: \(error)")
                    completion(.failure(error))
                }
            }
        )
    }
    
    // MARK: - Editor Management
    
    func addEditor(circleId: String, userId: String, completion: @escaping (Result<Circle, Error>) -> Void) {
        let body: [String: Any] = ["userId": userId]
        
        APIService.shared.request(
            endpoint: "circles/\(circleId)/editors",
            method: .post,
            body: body,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CircleDataResponse, APIError>) in
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func removeEditor(circleId: String, userId: String, completion: @escaping (Result<Circle, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(circleId)/editors/\(userId)",
            method: .delete,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CircleDataResponse, APIError>) in
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func getEditors(circleId: String, completion: @escaping (Result<[User], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(circleId)/editors",
            method: .get,
            requiresAuth: true,
            completion: { [weak self] (result: Result<EditorsResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    // MARK: - Update Circle Order
    
    func updateCircleOrder(circleIds: [String]) async throws {
        let body: [String: Any] = [
            "circleIds": circleIds
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            APIService.shared.request(
                endpoint: "users/me/circles/reorder",
                method: .put,
                body: body,
                requiresAuth: true,
                completion: { [weak self] (result: Result<EmptyResponse, APIError>) in
                    switch result {
                    case .success(_):
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            )
        }
    }
    
    // MARK: - Error Mapping
    
    private func mapAPIErrorToCircleError(_ error: APIError) -> CircleError {
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
            
        case .noInternet, .requestFailed, .invalidURL, .invalidResponse, .decodingFailed, .duplicateRequest:
            return .networkError(error)
            
        case .serverError, .unknown:
            return .unknown
        }
    }
    
    // MARK: - Share Link Functions
    
    func createShareLink(
        circleId: String,
        shareType: ShareType,
        accessLevel: AccessLevel,
        expiresIn: Int? = nil,
        targetUserId: String? = nil,
        email: String? = nil,
        completion: @escaping (Result<CircleShare, Error>) -> Void
    ) {
        var body: [String: Any] = [
            "shareType": shareType.rawValue,
            "accessLevel": accessLevel.rawValue
        ]
        
        if let expiresIn = expiresIn {
            body["expiresIn"] = expiresIn
        }
        
        if shareType == .registeredUser, let userId = targetUserId {
            body["userId"] = userId
        } else if shareType == .email, let email = email {
            body["email"] = email
        }
        
        APIService.shared.request(
            endpoint: "circles/\(circleId)/share",
            method: .post,
            body: body,
            requiresAuth: true,
            completion: { [weak self] (result: Result<ShareResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func getCircleShares(circleId: String, completion: @escaping (Result<[CircleShare], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(circleId)/shares",
            method: .get,
            requiresAuth: true,
            completion: { [weak self] (result: Result<SharesResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func revokeShare(circleId: String, shareId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(circleId)/share/\(shareId)",
            method: .delete,
            requiresAuth: true,
            completion: { [weak self] (result: Result<EmptyResponse, APIError>) in
                guard let self = self else { return }
                
                switch result {
                case .success(_):
                    completion(.success(true))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    // MARK: - Circle Likes and Comments
    
    func likeCircle(id: String, completion: @escaping (Result<Circle, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(id)/like",
            method: .post,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CircleLikeResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func fetchCircleLikes(id: String, completion: @escaping (Result<CircleLikesResponse, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(id)/likes",
            method: .get,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CircleLikesResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func getCircleComments(circleId: String, completion: @escaping (Result<[CircleComment], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(circleId)/comments",
            method: .get,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CircleCommentsResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func addCircleComment(circleId: String, text: String, completion: @escaping (Result<CircleComment, Error>) -> Void) {
        let requestBody = ["text": text]
        
        APIService.shared.request(
            endpoint: "circles/\(circleId)/comments",
            method: .post,
            body: requestBody,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CircleCommentResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func deleteCircleComment(circleId: String, commentId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(circleId)/comments/\(commentId)",
            method: .delete,
            requiresAuth: true,
            completion: { [weak self] (result: Result<EmptyResponse, APIError>) in
                switch result {
                case .success(_):
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func addCommentReply(circleId: String, commentId: String, text: String, completion: @escaping (Result<CircleComment, Error>) -> Void) {
        let requestBody = ["text": text]
        
        APIService.shared.request(
            endpoint: "circles/\(circleId)/comments/\(commentId)/replies",
            method: .post,
            body: requestBody,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CircleCommentResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func getCommentReplies(circleId: String, commentId: String, completion: @escaping (Result<[CircleComment], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(circleId)/comments/\(commentId)/replies",
            method: .get,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CircleCommentsResponse, APIError>) in
                switch result {
                case .success(let response):
                    completion(.success(response.data))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }
    
    func copyCircle(circleId: String, newName: String? = nil, completion: @escaping (Result<Circle, Error>) -> Void) {
        var requestBody: [String: Any] = [:]
        if let name = newName {
            requestBody["name"] = name
        }
        
        APIService.shared.request(
            endpoint: "circles/\(circleId)/copy",
            method: .post,
            body: requestBody.isEmpty ? nil : requestBody,
            requiresAuth: true,
            completion: { [weak self] (result: Result<CircleCopyResponse, APIError>) in
                guard let self = self else { return }
                
                switch result {
                case .success(let response):
                    // Return the new circle (caching is handled by the view controller)
                    completion(.success(response.circle))
                case .failure(let error):
                    let mappedError = self.mapAPIErrorToCircleError(error)
                    completion(.failure(mappedError))
                }
            }
        )
    }
}

// MARK: - Response Types

struct CirclesResponse: Decodable {
    let success: Bool
    let circles: [Circle]
}

struct CircleResponse: Decodable {
    let success: Bool
    let circle: Circle
}

struct CircleDataResponse: Decodable {
    let success: Bool
    let data: Circle
}

struct ImageUploadResponse: Decodable {
    let success: Bool
    let url: String
}

struct ShareResponse: Decodable {
    let success: Bool
    let data: CircleShare
}

struct SharesResponse: Decodable {
    let success: Bool
    let data: [CircleShare]
}

struct EditorsResponse: Decodable {
    let success: Bool
    let data: [User]
}

struct CircleLikeResponse: Decodable {
    let success: Bool
    let data: Circle
}

struct CircleLikesResponse: Decodable {
    let success: Bool
    let likes: [User]
}

struct CircleCommentsResponse: Decodable {
    let success: Bool
    let data: [CircleComment]
}

struct CircleCommentResponse: Decodable {
    let success: Bool
    let data: CircleComment
}

struct CircleCopyResponse: Decodable {
    let success: Bool
    let message: String
    let circle: Circle
}
