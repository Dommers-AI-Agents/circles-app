import Foundation

/// A person's id is one plain key: their users-record id, exactly as the
/// server sends it. Two ids are the same person only when they're equal.
/// (Until 2026-10 this split Apple's dotted "000454.<hex>.<n>" ids; an audit
/// of every stored reference found none left, so matching is now exact —
/// Wes, 2026-10-09.) The server still translates old spellings at sign-in.
class IDNormalizer {
    
    /// The id itself, or nil when missing/empty
    static func normalize(_ userId: String?) -> String? {
        guard let userId = userId, !userId.isEmpty else { return nil }
        return userId
    }
    
    /// Same person: both present and equal
    static func isSameUser(_ id1: String?, _ id2: String?) -> Bool {
        guard let id1 = normalize(id1), let id2 = normalize(id2) else { return false }
        return id1 == id2
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