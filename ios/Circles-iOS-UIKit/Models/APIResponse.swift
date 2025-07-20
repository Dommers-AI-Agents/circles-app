import Foundation

struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T
    let message: String?
}

// Simple response for endpoints that don't return data
struct SimpleAPIResponse: Codable {
    let success: Bool
    let message: String?
}

// Tutorial status response
struct TutorialStatusResponse: Codable {
    let success: Bool
    let hasCompletedTutorial: Bool
    let onboardingCompleted: Bool
}
