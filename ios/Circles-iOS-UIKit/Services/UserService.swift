import Foundation

enum UserError: Error, LocalizedError {
    case notFound
    case permissionDenied
    case invalidData
    // The server explained why it refused — always show its words
    case serverRejected(String)
    case updateFailed
    case networkError(Error)
    case alreadyFriends
    case friendRequestAlreadySent
    case friendRequestNotFound
    case unknown

    var errorDescription: String? {
        switch self {
        case .serverRejected(let message):
            return message
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
        Logger.debug("🚀 UserService: fetchUserProfile called")
        Logger.debug("🚀 UserService: userId parameter: \(userId ?? "nil")")
        Logger.debug("🚀 UserService: Using endpoint: \(endpoint)")
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<UserResponse, APIError>) in
            Logger.debug("📡 UserService: fetchUserProfile API callback received")
            guard let self = self else { 
                Logger.debug("⚠️ UserService: Self deallocated during fetch")
                return 
            }
            
            switch result {
            case .success(let response):
                Logger.debug("✅ UserService: Successfully fetched user profile")
                Logger.debug("✅ UserService: User ID: \(response.user.id)")
                Logger.debug("✅ UserService: User name: \(response.user.displayName)")
                completion(.success(response.user))
            case .failure(let error):
                Logger.debug("❌ UserService: Failed to fetch user profile: \(error)")
                Logger.debug("❌ UserService: Error type: \(type(of: error))")
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    /// `profilePictureUrl` covers avatars that need no upload (stock avatars are
    /// drawn on device and stored as a scheme string). Before it existed, the
    /// edit screen computed an avatar URL and then never sent it — picking an
    /// avatar silently did nothing.
    func updateUserProfile(displayName: String? = nil, firstName: String? = nil, lastName: String? = nil, phoneNumber: String? = nil, bio: String? = nil, location: String? = nil, zipcode: String? = nil, profilePicture: Data? = nil, profilePictureUrl: String? = nil, completion: @escaping (Result<User, Error>) -> Void) {

        // An uploaded photo wins over a picked avatar when both are present
        if profilePicture == nil, let url = profilePictureUrl {
            performUpdateProfile(displayName: displayName, firstName: firstName, lastName: lastName, phoneNumber: phoneNumber, bio: bio, location: location, zipcode: zipcode, profilePictureUrl: url, completion: completion)
            return
        }

        // First check if we need to upload an image
        if let imageData = profilePicture {
            uploadProfileImage(imageData) { [weak self] result in
                switch result {
                case .success(let imageUrl):
                    // Now update the profile with the image URL
                    self?.performUpdateProfile(displayName: displayName, firstName: firstName, lastName: lastName, phoneNumber: phoneNumber, bio: bio, location: location, zipcode: zipcode, profilePictureUrl: imageUrl, completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            // Update profile without changing image
            performUpdateProfile(displayName: displayName, firstName: firstName, lastName: lastName, phoneNumber: phoneNumber, bio: bio, location: location, zipcode: zipcode, profilePictureUrl: nil, completion: completion)
        }
    }
    
    private func performUpdateProfile(displayName: String?, firstName: String?, lastName: String?, phoneNumber: String?, bio: String?, location: String?, zipcode: String?, profilePictureUrl: String?, completion: @escaping (Result<User, Error>) -> Void) {
        
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
        
        if let zipcode = zipcode {
            body["zipcode"] = zipcode
        }
        
        if let profilePictureUrl = profilePictureUrl {
            body["profilePicture"] = profilePictureUrl
        }
        
        // Debug logging
        Logger.debug("🔍 UserService - performUpdateProfile sending body:")
        Logger.debug("   - displayName: \(body["displayName"] ?? "nil")")
        Logger.debug("   - firstName: \(body["firstName"] ?? "nil")")
        Logger.debug("   - lastName: \(body["lastName"] ?? "nil")")
        Logger.debug("   - phoneNumber: \(body["phoneNumber"] ?? "nil")")
        Logger.debug("   - bio: \(body["bio"] ?? "nil")")
        Logger.debug("   - location: \(body["location"] ?? "nil")")
        Logger.debug("   - zipcode: \(body["zipcode"] ?? "nil")")
        Logger.debug("   - profilePicture: \(body["profilePicture"] ?? "nil")")
        
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
    
    /// Reports an app open (launch or return to foreground) so the backend
    /// can track when users actually come back, and on what version.
    /// Throttled client-side so rapid foreground flips don't inflate counts.
    private static let lastAppOpenReportKey = "lastAppOpenReportedAt"
    private static let appOpenReportInterval: TimeInterval = 5 * 60

    func reportAppOpen() {
        let now = Date()
        if let last = UserDefaults.standard.object(forKey: Self.lastAppOpenReportKey) as? Date,
           now.timeIntervalSince(last) < Self.appOpenReportInterval {
            return
        }
        UserDefaults.standard.set(now, forKey: Self.lastAppOpenReportKey)

        let info = Bundle.main.infoDictionary
        let body: [String: Any] = [
            "appVersion": info?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": info?["CFBundleVersion"] as? String ?? "unknown",
            "platform": "ios"
        ]

        APIService.shared.request(
            endpoint: "users/me/app-open",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            if case .failure(let error) = result {
                // Best-effort telemetry — never surface to the user
                Logger.debug("📊 App-open report failed: \(error)")
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
    
    /// The people the signed-in user follows.
    ///
    /// Follow is the low-friction first step in the network, so this list is
    /// usually much larger than the connection list and is what the People tab
    /// leans on. The server stamps `followsYou` on each entry, which is how the
    /// UI tells a one-way follow from a mutual one.
    func getFollowing(completion: @escaping (Result<[User], Error>) -> Void) {
        guard let userId = AuthService.shared.getUserId() else {
            completion(.failure(APIError.unauthorized))
            return
        }

        APIService.shared.request(
            endpoint: "users/\(userId)/following",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<FollowingResponse, APIError>) in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                completion(.success(response.following))
            case .failure(let error):
                completion(.failure(self.mapAPIErrorToUserError(error)))
            }
        }
    }

    /// The people who follow the signed-in user. Each entry carries
    /// `isFollowing` (whether the caller follows them back), which is what the
    /// People tab's "Follows you" / Follow Back section keys on.
    func getFollowers(completion: @escaping (Result<[User], Error>) -> Void) {
        guard let userId = AuthService.shared.getUserId() else {
            completion(.failure(APIError.unauthorized))
            return
        }

        APIService.shared.request(
            endpoint: "users/\(userId)/followers",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<FollowersResponse, APIError>) in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                completion(.success(response.followers))
            case .failure(let error):
                completion(.failure(self.mapAPIErrorToUserError(error)))
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
                Logger.debug("Profile image upload failed: \(error)")
                let mappedError = self.mapAPIErrorToUserError(error)
                completion(.failure(mappedError))
            }
        }
    }
    
    // MARK: - Error Mapping
    
    private func mapAPIErrorToUserError(_ error: APIError) -> UserError {
        switch error {
        case .httpError(let statusCode, _):
            // Flow-control cases first (UI branches on these), matched against
            // the server message in either response shape
            if let serverMessage = error.serverMessage {
                let lowered = serverMessage.lowercased()
                if lowered.contains("already friends") {
                    return .alreadyFriends
                } else if lowered.contains("friend request already sent") {
                    return .friendRequestAlreadySent
                } else if lowered.contains("friend request not found") {
                    return .friendRequestNotFound
                }
                // Otherwise the server's explanation beats a canned status string
                return .serverRejected(serverMessage)
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
            
        case .rateLimited:
            return .networkError(error)
            
        case .serverError, .unknown, .processingFailed, .processingTimeout:
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
    
    // MARK: - Account Merge Methods
    
    static func findDuplicateAccounts(for user: User, completion: @escaping (Result<[User], Error>) -> Void) {
        let body: [String: Any] = [
            "email": user.email ?? "",
            "displayName": user.displayName
        ]
        
        APIService.shared.request(
            endpoint: "users/find-duplicates",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<DuplicateAccountsResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.duplicateAccounts))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    static func mergeAccounts(primaryId: String, secondaryId: String, completion: @escaping (Result<User, Error>) -> Void) {
        let body: [String: Any] = [
            "primaryAccountId": primaryId,
            "secondaryAccountId": secondaryId
        ]
        
        APIService.shared.request(
            endpoint: "users/merge-accounts",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<MergeAccountsResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.primaryAccount))
            case .failure(let error):
                completion(.failure(error))
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
    /// Lossy: one undecodable person must not empty the whole list.
    let users: [User]

    private enum CodingKeys: String, CodingKey { case success, users }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? container.decode(Bool.self, forKey: .success)) ?? true
        users = (try? container.decode(LossyDecodableArray<User>.self, forKey: .users))?.elements ?? []
    }
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