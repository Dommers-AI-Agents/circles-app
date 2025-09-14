import Foundation

class BlockService {
    static let shared = BlockService()
    
    private init() {}
    
    // MARK: - Block User
    
    func blockUser(userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "blocks/user/\(userId)",
            method: .post,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                // Clear any cached data for this user
                self.clearUserFromCache(userId: userId)
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Unblock User
    
    func unblockUser(userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "blocks/user/\(userId)",
            method: .delete,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Check Block Status
    
    struct BlockStatus: Codable {
        let success: Bool
        let isBlockedByMe: Bool
        let hasBlockedMe: Bool
        let isBlocked: Bool
    }
    
    func checkBlockStatus(userId: String, completion: @escaping (Result<BlockStatus, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "blocks/check/\(userId)",
            method: .get,
            requiresAuth: true
        ) { (result: Result<BlockStatus, APIError>) in
            switch result {
            case .success(let status):
                completion(.success(status))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Get Blocked Users
    
    struct BlockedUsersResponse: Codable {
        let success: Bool
        let blocks: [Block]
        let hasMore: Bool
    }
    
    struct Block: Codable {
        let id: String
        let blockerId: String
        let blockedUserId: String
        let createdAt: String
        let updatedAt: String
        let blockedUser: User?
    }
    
    func getBlockedUsers(limit: Int = 50, startAfter: String? = nil, completion: @escaping (Result<BlockedUsersResponse, Error>) -> Void) {
        var queryParams: [String: String] = [
            "limit": String(limit)
        ]
        
        if let startAfter = startAfter {
            queryParams["startAfter"] = startAfter
        }
        
        APIService.shared.request(
            endpoint: "blocks",
            method: .get,
            queryParams: queryParams,
            requiresAuth: true
        ) { (result: Result<BlockedUsersResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func clearUserFromCache(userId: String) {
        // Clear from various caches to ensure blocked user's content is removed
        
        // Post notification so UI components can update
        // NetworkManager will refresh connections list when needed
        NotificationCenter.default.post(name: .userBlocked, object: nil, userInfo: ["userId": userId])
        
        // Note: UI components should handle hiding conversations with blocked users
        // MessagingService will filter out blocked users in conversation lists
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let userBlocked = Notification.Name("userBlocked")
    static let userUnblocked = Notification.Name("userUnblocked")
}