import Foundation

struct Comment: Codable {
    let id: String
    let suggestionId: String
    let userId: String
    let userDetails: User?
    let message: String
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case suggestionId
        case userId
        case userDetails
        case message
        case createdAt
        case updatedAt
    }
    
    // Helper properties
    var isCurrentUserComment: Bool {
        return userId == AuthService.shared.getUserId()
    }
    
    var displayAuthorName: String {
        if isCurrentUserComment {
            return "You"
        }
        return userDetails?.displayName ?? "Unknown User"
    }
}

// Response types
struct CommentResponse: Codable {
    let success: Bool
    let data: Comment
}

struct CommentsResponse: Codable {
    let success: Bool
    let data: [Comment]
}