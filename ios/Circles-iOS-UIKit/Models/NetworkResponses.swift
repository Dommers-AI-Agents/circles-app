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

// NOTE: GET /users/:id/following decodes into `FollowingResponse`, which is
// declared alongside its first consumer in
// Controllers/Profile/FollowersListViewController.swift.