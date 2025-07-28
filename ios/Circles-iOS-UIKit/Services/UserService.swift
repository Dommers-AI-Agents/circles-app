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
    
    // MARK: - Helper Methods
    
    /// Helper function to create a type-safe completion handler for API requests
    private func createAPICompletion<T>(_ completion: @escaping (Result<T, Error>) -> Void) -> (Result<T, APIError>) -> Void {
        return { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    // MARK: - User Profile
    
    func fetchUserProfile(userId: String? = nil, completion: @escaping (Result<User, Error>) -> Void) {
        let endpoint = userId != nil ? "users/\(userId!)" : "users/me"
        print("🚀 UserService: fetchUserProfile called")
        print("🚀 UserService: userId parameter: \(userId ?? "nil")")
        print("🚀 UserService: Using endpoint: \(endpoint)")
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<UserResponse, APIError>) in
            print("📡 UserService: fetchUserProfile API callback received")
            guard let self = self else { 
                print("⚠️ UserService: Self deallocated during fetch")
                return 
            }
            
            switch result {
            case .success(let response):
                print("✅ UserService: Successfully fetched user profile")
                print("✅ UserService: User ID: \(response.user.id)")
                print("✅ UserService: User name: \(response.user.displayName)")
                completion(.success(response.user))
            case .failure(let error):
                print("❌ UserService: Failed to fetch user profile: \(error)")
                print("❌ UserService: Error type: \(type(of: error))")
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    func updateUserProfile(displayName: String? = nil, firstName: String? = nil, lastName: String? = nil, phoneNumber: String? = nil, bio: String? = nil, location: String? = nil, profilePicture: Data? = nil, completion: @escaping (Result<User, Error>) -> Void) {
        
        // First check if we need to upload an image
        if let imageData = profilePicture {
            uploadProfileImage(imageData) { [weak self] result in
                switch result {
                case .success(let imageUrl):
                    // Now update the profile with the image URL
                    self?.performUpdateProfile(displayName: displayName, firstName: firstName, lastName: lastName, phoneNumber: phoneNumber, bio: bio, location: location, profilePictureUrl: imageUrl, completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            // Update profile without changing image
            performUpdateProfile(displayName: displayName, firstName: firstName, lastName: lastName, phoneNumber: phoneNumber, bio: bio, location: location, profilePictureUrl: nil, completion: completion)
        }
    }
    
    private func performUpdateProfile(displayName: String?, firstName: String?, lastName: String?, phoneNumber: String?, bio: String?, location: String?, profilePictureUrl: String?, completion: @escaping (Result<User, Error>) -> Void) {
        
        var body: [String: Any] = [:]
        
        if let displayName = displayName {
            body["displayName"] = displayName
        }
        
        // Always include these fields (even if empty) to ensure they're saved
        if let firstName = firstName {
            body["firstName"] = firstName
        }
        
        if let lastName = lastName {
            body["lastName"] = lastName
        }
        
        if let phoneNumber = phoneNumber {
            body["phoneNumber"] = phoneNumber
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
        
        // Debug logging
        print("🔍 UserService - performUpdateProfile sending body:")
        print("   - displayName: \(body["displayName"] ?? "nil")")
        print("   - firstName: \(body["firstName"] ?? "nil")")
        print("   - lastName: \(body["lastName"] ?? "nil")")
        print("   - phoneNumber: \(body["phoneNumber"] ?? "nil")")
        print("   - bio: \(body["bio"] ?? "nil")")
        print("   - location: \(body["location"] ?? "nil")")
        print("   - profilePicture: \(body["profilePicture"] ?? "nil")")
        
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
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response.user))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    func updateUserPreferences(defaultHomeView: String?, completion: @escaping (Result<User, Error>) -> Void) {
        var body: [String: Any] = ["preferences": [:]]
        
        if let defaultHomeView = defaultHomeView {
            body["preferences"] = ["defaultHomeView": defaultHomeView]
        }
        
        APIService.shared.request(
            endpoint: "users/me",
            method: .put,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<UserResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response.user))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    func updateNotificationPreferences(_ preferences: NotificationPreferences, completion: @escaping (Result<User, Error>) -> Void) {
        let body: [String: Any] = [
            "notificationPreferences": [
                "newMessages": preferences.newMessages,
                "newSuggestions": preferences.newSuggestions,
                "newPlaces": preferences.newPlaces,
                "connectionRequests": preferences.connectionRequests,
                "circleInvites": preferences.circleInvites,
                "newFollowers": preferences.newFollowers,
                "dailyDigest": preferences.dailyDigest,
                "dailySummary": preferences.dailySummary,
                "summaryTime": preferences.summaryTime,
                "timezone": preferences.timezone,
                "socialActivity": preferences.socialActivity,
                "discoveryPrompts": preferences.discoveryPrompts,
                "milestones": preferences.milestones,
                "weekendRecommendations": preferences.weekendRecommendations,
                "reengagement": preferences.reengagement,
                "frequency": preferences.frequency,
                "quietHoursEnabled": preferences.quietHoursEnabled,
                "quietHoursStart": preferences.quietHoursStart,
                "quietHoursEnd": preferences.quietHoursEnd
            ]
        ]
        
        APIService.shared.request(
            endpoint: "users/notification-preferences",
            method: .put,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<UserResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response.user))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    // MARK: - User Search
    
    func searchUsers(query: String, completion: @escaping (Result<[User], Error>) -> Void) {
        let queryParams = ["query": query]
        
        APIService.shared.request(
            endpoint: "users/search",
            method: .get,
            queryParams: queryParams,
            requiresAuth: true
        ) { [weak self] (result: Result<UsersResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response.users))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
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
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response.users))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    func getFriendRequests(completion: @escaping (Result<[FriendRequest], Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/me/friend-requests",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<FriendRequestsResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response.friendRequests))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
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
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    func acceptFriendRequest(requestId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/friend-request/\(requestId)/accept",
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    func rejectFriendRequest(requestId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/friend-request/\(requestId)/reject",
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    func removeFriend(userId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/friend/\(userId)",
            method: .delete,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                completion(.success(true))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func uploadProfileImage(_ imageData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        // Convert to base64
        let base64String = imageData.base64EncodedString()
        
        // Upload to backend
        APIService.shared.request(
            endpoint: "upload/image",
            method: .post,
            body: [
                "image": base64String,
                "filename": "profile_\(UUID().uuidString).jpg"
            ],
            requiresAuth: true
        ) { [weak self] (result: Result<UploadResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                completion(.success(response.url))
            case .failure(let error):
                print("Profile image upload failed: \(error)")
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
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
            
        case .noInternet, .requestFailed, .invalidURL, .invalidResponse, .decodingFailed, .duplicateRequest:
            return .networkError(error)
            
        case .serverError, .unknown:
            return .unknown
        }
    }
    
    func deleteAccount(completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "users/me",
            method: .delete,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    func changePassword(currentPassword: String, newPassword: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let body: [String: Any] = [
            "currentPassword": currentPassword,
            "newPassword": newPassword
        ]
        
        APIService.shared.request(
            endpoint: "users/change-password",
            method: .post,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    func reorderCircles(circleIds: [String], completion: @escaping (Error?) -> Void) {
        let body: [String: Any] = ["circleIds": circleIds]
        
        APIService.shared.request(
            endpoint: "users/me/circles/reorder",
            method: .put,
            body: body,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            guard let self = self else { return }
            
            switch result {
            case .success:
                completion(nil)
            case .failure(let error):
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(mappedError)
            }
        }
    }
}

// MARK: - Response Types

// UserResponse is defined in AuthService.swift

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

struct UploadResponse: Decodable {
    let success: Bool
    let url: String
}


struct UsersSearchResponse: Decodable {
    let success: Bool
    let users: [User]
}