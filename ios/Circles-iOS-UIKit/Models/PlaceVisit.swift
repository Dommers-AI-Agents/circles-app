import Foundation

// MARK: - PlaceVisit Model

struct PlaceVisit: Codable {
    var id: String  // Made mutable to update with server ID
    let userId: String
    let placeName: String
    let placeAddress: String
    let latitude: Double
    let longitude: Double
    let category: String?
    let visitedAt: Date
    var duration: Int // minutes
    let autoDetected: Bool
    var reviewed: Bool
    var dismissed: Bool
    var synced: Bool = false
    var notes: String?
    var photos: [String] = []
    var addedToCircles: [String] = []
    var horizontalAccuracy: Double? // in meters
}

// MARK: - Response Models

struct VisitResponse: Codable {
    let success: Bool
    let data: VisitData
}

struct VisitData: Codable {
    let id: String
    let userId: String
    let placeName: String
    let placeAddress: String
    let visitedAt: String
    let duration: Int
    let category: String?
    let location: Location?
    let autoDetected: Bool?
    let reviewed: Bool?
    let dismissed: Bool?
    let notes: String?
    let photos: [String]?
    let addedToCircles: [String]?
    let horizontalAccuracy: Double?
    
    struct Location: Codable {
        let latitude: Double
        let longitude: Double
    }
}

// MARK: - Convenience Extension

extension PlaceVisit {
    static func from(_ data: VisitData) -> PlaceVisit {
        return PlaceVisit(
            id: data.id,
            userId: data.userId,
            placeName: data.placeName,
            placeAddress: data.placeAddress,
            latitude: data.location?.latitude ?? 0,
            longitude: data.location?.longitude ?? 0,
            category: data.category,
            visitedAt: ISO8601DateFormatter().date(from: data.visitedAt) ?? Date(),
            duration: data.duration,
            autoDetected: data.autoDetected ?? false,
            reviewed: data.reviewed ?? false,
            dismissed: data.dismissed ?? false,
            synced: true,
            notes: data.notes,
            photos: data.photos ?? [],
            addedToCircles: data.addedToCircles ?? [],
            horizontalAccuracy: data.horizontalAccuracy
        )
    }
}