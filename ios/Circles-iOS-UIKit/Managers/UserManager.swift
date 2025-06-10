import SwiftUI
import Combine

class UserManager: ObservableObject {
    static let shared = UserManager()
    
    @Published var user: User?
    @Published var friends: [User] = []
    @Published var friendRequests: [FriendRequest] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private let userService = UserService.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    func fetchUser(userId: String) async throws -> User {
        try await withCheckedThrowingContinuation { continuation in
            userService.fetchUserProfile(userId: userId) { result in
                switch result {
                case .success(let user):
                    continuation.resume(returning: user)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func updateProfile(displayName: String, bio: String?, location: String?, profileImage: UIImage?) async throws {
        guard let currentUser = AuthManager.shared.currentUser else {
            throw AuthError.tokenExpired
        }
        
        try await withCheckedThrowingContinuation { continuation in
            userService.updateUserProfile(
                displayName: displayName,
                bio: bio,
                location: location,
                profilePicture: profileImage?.jpegData(compressionQuality: 0.8)
            ) { [weak self] result in
                switch result {
                case .success(let updatedUser):
                    DispatchQueue.main.async {
                        self?.user = updatedUser
                        // Update auth manager's current user
                        AuthManager.shared.currentUser = updatedUser
                    }
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func fetchFriends() async {
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let fetchedFriends = try await withCheckedThrowingContinuation { continuation in
                userService.getFriends { result in
                    switch result {
                    case .success(let friends):
                        continuation.resume(returning: friends)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            await MainActor.run {
                self.friends = fetchedFriends
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    func fetchFriendRequests() async {
        do {
            let requests = try await withCheckedThrowingContinuation { continuation in
                userService.getFriendRequests { result in
                    switch result {
                    case .success(let requests):
                        continuation.resume(returning: requests)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            await MainActor.run {
                self.friendRequests = requests
            }
        } catch {
            print("Failed to fetch friend requests: \(error)")
        }
    }
    
    func sendFriendRequest(to userId: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            userService.sendFriendRequest(userId: userId) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func acceptFriendRequest(from userId: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            userService.acceptFriendRequest(requestId: userId) { [weak self] result in
                switch result {
                case .success:
                    DispatchQueue.main.async {
                        self?.friendRequests.removeAll { $0.id == userId }
                    }
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        
        // Refresh friends list
        await fetchFriends()
    }
    
    func rejectFriendRequest(from userId: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            userService.rejectFriendRequest(requestId: userId) { [weak self] result in
                switch result {
                case .success:
                    DispatchQueue.main.async {
                        self?.friendRequests.removeAll { $0.id == userId }
                    }
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func removeFriend(userId: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            userService.removeFriend(userId: userId) { [weak self] result in
                switch result {
                case .success:
                    DispatchQueue.main.async {
                        self?.friends.removeAll { $0.id == userId }
                    }
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}