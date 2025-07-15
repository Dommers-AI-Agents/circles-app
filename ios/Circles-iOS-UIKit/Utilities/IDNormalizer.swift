import Foundation

/// Utility class to handle user ID normalization between complex and simple formats
/// Complex format: 000454.9b5eeac93282416c9bc6dcecbc49b40f.2127
/// Simple format: 9b5eeac93282416c9bc6dcecbc49b40f
class IDNormalizer {
    
    /// Normalizes a user ID to its simple format
    /// - Parameter userId: The user ID to normalize (can be complex or simple format)
    /// - Returns: The normalized (simple) user ID, or the original if already simple
    static func normalize(_ userId: String?) -> String? {
        guard let userId = userId, !userId.isEmpty else { return nil }
        
        // If complex format (contains dots), extract the Firebase UID (middle part)
        if userId.contains(".") {
            let parts = userId.split(separator: ".")
            if parts.count >= 2 {
                let normalizedId = String(parts[1])
                print("📋 IDNormalizer: Normalized \(userId) → \(normalizedId)")
                return normalizedId
            }
        }
        
        // Already in simple format
        return userId
    }
    
    /// Check if two IDs refer to the same user
    /// - Parameters:
    ///   - id1: First user ID
    ///   - id2: Second user ID
    /// - Returns: True if IDs refer to the same user
    static func isSameUser(_ id1: String?, _ id2: String?) -> Bool {
        guard let id1 = id1, let id2 = id2 else { return false }
        return normalize(id1) == normalize(id2)
    }
    
    /// Check if an ID is in complex format
    /// - Parameter userId: The user ID to check
    /// - Returns: True if ID is in complex format
    static func isComplexId(_ userId: String?) -> Bool {
        return userId?.contains(".") ?? false
    }
    
    /// Extract the simple ID from a Connection based on current user
    /// - Parameters:
    ///   - connection: The connection object
    ///   - currentUserId: The current user's ID
    /// - Returns: The normalized other user's ID
    static func getOtherUserId(from connection: Connection, currentUserId: String) -> String? {
        let currentNormalized = normalize(currentUserId)
        let userIdNormalized = normalize(connection.userId)
        let connectedUserIdNormalized = normalize(connection.connectedUserId)
        
        // Return the ID that doesn't match the current user
        if isSameUser(currentUserId, connection.userId) {
            return connectedUserIdNormalized
        } else {
            return userIdNormalized
        }
    }
}