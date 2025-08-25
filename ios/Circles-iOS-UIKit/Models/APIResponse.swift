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

// Video response for single video fetch
struct PlaceVideoResponse: Codable {
    let success: Bool
    let data: PlaceVideo
    let message: String?
}

// Daily Summary Response models are defined in APIService.swift
