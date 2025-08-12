import Foundation

// Response model for discovery users endpoints
struct DiscoveryUsersResponse: Codable {
    let success: Bool
    let users: [User]
    let count: Int
}

// Response model for user search endpoints
struct SearchUsersResponse: Codable {
    let success: Bool
    let users: [User]
    let count: Int
    let query: String
}