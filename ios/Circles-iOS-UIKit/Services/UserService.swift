import Foundation

enum UserError: Error, LocalizedError {
    case notFound
    case permissionDenied
    case invalidData
    case updateFailed
    case networkError(Error)
    case alreadyFriends
    case friendRequestAlreadySent
    case friendRequestNotFound
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "User not found"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        case .invalidData:
            return "Invalid user data"
        case .updateFailed:
            return "Failed to update user"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .alreadyFriends:
            return "You are already friends with this user"
        case .friendRequestAlreadySent:
            return "Friend request already sent"
        case .friendRequestNotFound:
            return "Friend request not found"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

class UserService {
    static let shared = UserService()
    
    private init() {}
    
    // MARK: - User Profile
    
    func fetchUserProfile(userId: String? = nil, completion: @escaping (Result<User, Error>) -> Void) {
        let endpoint = userId != nil ? "users/\(userId!)" : "users/me"
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<UserResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.user))
            case .failure(let error):
                let userError = self?.mapAPIErrorToUserError(error)
                completion(.failure(userError ?? error))
            }
        }
    }
    
    func updateUserProfile(displayName: String? = nil, bio: String? = nil, location: String? = nil, profilePicture: Data? = nil, completion: @escaping (Result<User, Error>) -> Void) {
        
        // First check if we need to upload an image
        if let imageData = profilePicture {
            uploadProfileImage(imageData) { [weak self] result in
                switch result {
                case .success(let imageUrl):
                    // Now update the profile with the image URL
                    self?.performUpdateProfile(displayName: displayName, bio: bio, location: location, profilePictureUrl: imageUrl, completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            // Update profile without changing image
            performUpdateProfile(displayName: displayName, bio: bio, location: location, profilePictureUrl: nil, completion: completion)
        }
    }
    
    private func performUpdateProfile(displayName: String?, bio: String?, location: String?, profilePictureUrl: String?, completion: @escaping (Result<User, Error>) -> Void) {
        
        var body: [String: Any] = [:]
        
        if let displayName = displayName {
            body["displayName"] = displayName
        }
        
        if let bio = bio {
            body["bio"] = bio
        }
        
        if let location = location {
            body["location"] = location
        }
        
        if let profilePictureUrl = profilePictureUrl {
            body["profilePicture"] = profilePictureUrl
        }
        
        // Only proceed if there are changes to make
        guard !body.isEmpty else {
            completion(.failure(UserError.invalidData))
            return
        }
        
        APIService.shared.request(
            endpoint: "users/me",
            method: .put,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<UserResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.user))
            case .failure(let error):
                let userError = self?.mapAPIErrorToUserError(error)
                completion(.failure(userError ?? UserError.updateFailed))
            }
        }
    }
    
    // MARK: - User Search
    
    func searchUsers(query: String, completion: @escaping (Result<[User], Error>) -> Void) {
        let queryParams = ["q": query]
        
        APIService.shared.request(
            endpoint: "users/search",
            method: .get,
            queryParams: queryParams,
            requiresAuth: true
        ) { [weak self] (result: Result<UsersResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.users))
            case .failure(let error):
                let userError = self?.mapAPIErrorToUserError(error)
                completion(.failure(userError ?? error))
            }
        }
    }
    
    // MARK: - Friend Management
    
    func getFriends(completion: @escaping (Result<[User], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/me/friends",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<UsersResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.users))
            case .failure(let error):
                let userError = self?.mapAPIErrorToUserError(error)
                completion(.failure(userError ?? error))
            }
        }
    }
    
    func getFriendRequests(completion: @escaping (Result<[FriendRequest], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/me/friend-requests",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<FriendRequestsResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.friendRequests))
            case .failure(let error):
                let userError = self?.mapAPIErrorToUserError(error)
                completion(.failure(userError ?? error))
            }
        }
    }
    
    func sendFriendRequest(userId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let body = ["userId": userId]
        
        APIService.shared.request(
            endpoint: "users/friend-request",
            method: .post,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                let userError = self?.mapAPIErrorToUserError(error)
                completion(.failure(userError ?? error))
            }
        }
    }
    
    func acceptFriendRequest(requestId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/friend-request/\(requestId)/accept",
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                let userError = self?.mapAPIErrorToUserError(error)
                completion(.failure(userError ?? error))
            }
        }
    }
    
    func rejectFriendRequest(requestId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/friend-request/\(requestId)/reject",
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                let userError = self?.mapAPIErrorToUserError(error)
                completion(.failure(userError ?? error))
            }
        }
    }
    
    func removeFriend(userId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/friend/\(userId)",
            method: .delete,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                let userError = self?.mapAPIErrorToUserError(error)
                completion(.failure(userError ?? error))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func uploadProfileImage(_ imageData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        // In a real app, this would upload the image to a cloud storage service
        // For now, we'll simulate it with a mock URL
        
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            // Generate a mock image URL
            let mockImageUrl = "https://storage.circles-app.com/profiles/\(UUID().uuidString).jpg"
            completion(.success(mockImageUrl))
        }
    }
    
    // MARK: - Error Mapping
    
    private func mapAPIErrorToUserError(_ error: APIError) -> UserError {
        switch error {
        case .httpError(let statusCode, let data):
            if let data = data, let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                // Check for specific error messages in the response
                let errorMessage = errorResponse.message.lowercased()
                
                if errorMessage.contains("already friends") {
                    return .alreadyFriends
                } else if errorMessage.contains("friend request already sent") {
                    return .friendRequestAlreadySent
                } else if errorMessage.contains("friend request not found") {
                    return .friendRequestNotFound
                }
            }
            
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

// Using the same UserResponse as AuthService

struct UsersResponse: Decodable {
    let success: Bool
    let users: [User]
}

struct FriendRequest: Codable, Identifiable {
    let id: String
    let from: User
    let to: User
    let status: FriendRequestStatus
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case from, to, status, createdAt
    }
}

enum FriendRequestStatus: String, Codable {
    case pending
    case accepted
    case rejected
}

struct FriendRequestsResponse: Decodable {
    let success: Bool
    let friendRequests: [FriendRequest]
}