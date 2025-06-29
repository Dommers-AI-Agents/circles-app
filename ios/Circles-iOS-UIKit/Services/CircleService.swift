import Foundation

enum CircleError: Error, LocalizedError {
    case notFound
    case permissionDenied
    case invalidData
    case creationFailed
    case updateFailed
    case deleteFailed
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
    
    // MARK: - Fetch Circles
    
    func fetchUserCircles(completion: @escaping (Result<[Circle], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/me",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<CirclesResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.circles))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    func fetchUserCircles(userId: String, completion: @escaping (Result<[Circle], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/\(userId)/circles",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<CirclesResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.circles))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    func fetchCircleById(id: String, completion: @escaping (Result<Circle, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(id)",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<CircleResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.circle))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError ?? error))
            }
        }
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
            requiresAuth: true
        ) { [weak self] (result: Result<CirclesResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.circles))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError ?? error))
            }
        }
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
            requiresAuth: true
        ) { [weak self] (result: Result<CirclesResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.circles))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    // MARK: - Create, Update, Delete
    
    func createCircle(name: String, description: String?, privacy: PrivacyLevel, category: CircleCategory, location: String? = nil, tags: [String]? = nil, coverImage: Data? = nil, completion: @escaping (Result<Circle, Error>) -> Void) {
        
        // First check if we need to upload an image
        if let imageData = coverImage {
            uploadImage(imageData) { [weak self] result in
                switch result {
                case .success(let imageUrl):
                    // Now create the circle with the image URL
                    self?.performCreateCircle(name: name, description: description, privacy: privacy, category: category, location: location, tags: tags, coverImageUrl: imageUrl, completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            // Create circle without image
            performCreateCircle(name: name, description: description, privacy: privacy, category: category, location: location, tags: tags, coverImageUrl: nil, completion: completion)
        }
    }
    
    private func performCreateCircle(name: String, description: String?, privacy: PrivacyLevel, category: CircleCategory, location: String?, tags: [String]?, coverImageUrl: String?, completion: @escaping (Result<Circle, Error>) -> Void) {
        
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
        
        APIService.shared.request(
            endpoint: "circles",
            method: .post,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<CircleResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.circle))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError ?? CircleError.creationFailed))
            }
        }
    }
    
    func updateCircle(id: String, name: String? = nil, description: String? = nil, privacy: PrivacyLevel? = nil, category: CircleCategory? = nil, location: String? = nil, tags: [String]? = nil, coverImage: Data? = nil, completion: @escaping (Result<Circle, Error>) -> Void) {
        
        // First check if we need to upload an image
        if let imageData = coverImage {
            uploadImage(imageData) { [weak self] result in
                switch result {
                case .success(let imageUrl):
                    // Now update the circle with the image URL
                    self?.performUpdateCircle(id: id, name: name, description: description, privacy: privacy, category: category, location: location, tags: tags, coverImageUrl: imageUrl, completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            // Update circle without changing image
            performUpdateCircle(id: id, name: name, description: description, privacy: privacy, category: category, location: location, tags: tags, coverImageUrl: nil, completion: completion)
        }
    }
    
    private func performUpdateCircle(id: String, name: String?, description: String?, privacy: PrivacyLevel?, category: CircleCategory?, location: String?, tags: [String]?, coverImageUrl: String?, completion: @escaping (Result<Circle, Error>) -> Void) {
        
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
            requiresAuth: true
        ) { [weak self] (result: Result<CircleResponse, APIError>) in
            switch result {
            case .success(let response):
                print("Circle updated successfully with coverImage: \(response.circle.coverImage ?? "nil")")
                completion(.success(response.circle))
            case .failure(let error):
                print("Circle update failed: \(error)")
                let mappedError = self?.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError ?? CircleError.updateFailed))
            }
        }
    }
    
    func deleteCircle(id: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(id)",
            method: .delete,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError ?? CircleError.deleteFailed))
            }
        }
    }
    
    // MARK: - Social Functions
    
    func shareCircle(id: String, userIds: [String], completion: @escaping (Result<Bool, Error>) -> Void) {
        let body: [String: Any] = ["userIds": userIds]
        
        APIService.shared.request(
            endpoint: "circles/\(id)/share",
            method: .post,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    func followCircle(id: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(id)/follow",
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError ?? error))
            }
        }
    }
    
    func unfollowCircle(id: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "circles/\(id)/unfollow",
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                let mappedError = self?.mapAPIErrorToCircleError(error)
                completion(.failure(mappedError ?? error))
            }
        }
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
            requiresAuth: true
        ) { (result: Result<ImageUploadResponse, APIError>) in
            switch result {
            case .success(let response):
                print("Image uploaded successfully: \(response.url)")
                completion(.success(response.url))
            case .failure(let error):
                print("Image upload failed: \(error)")
                completion(.failure(error))
            }
        }
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
                requiresAuth: true
            ) { [weak self] (result: Result<EmptyResponse, APIError>) in
                switch result {
                case .success(_):
                    continuation.resume()
                case .failure(let error):
                    let mappedError = self?.mapAPIErrorToCircleError(error) ?? CircleError.unknown
                    continuation.resume(throwing: mappedError)
                }
            }
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
            
        case .noInternet, .requestFailed, .invalidURL, .invalidResponse, .decodingFailed:
            return .networkError(error)
            
        case .serverError, .unknown:
            return .unknown
        }
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

struct ImageUploadResponse: Decodable {
    let success: Bool
    let url: String
}