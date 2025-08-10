import Foundation
import CoreLocation

struct CheckIn: Codable, Identifiable {
    let id: String
    let userId: String
    let userName: String
    let userPhoto: String?
    let placeId: String?
    let placeName: String
    let placeAddress: String
    let location: CheckInLocation?
    let placeCategory: String?
    let circleId: String?
    let message: String?
    let startTime: Date
    let endTime: Date
    let duration: String
    let notifiedGroups: [String]
    let notifiedUsers: [String]
    let showInActivityFeed: Bool
    let responses: [CheckInResponse]
    let active: Bool
    let createdAt: Date
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId, userName, userPhoto, placeId, placeName, placeAddress, location
        case placeCategory, circleId, message, startTime, endTime, duration
        case notifiedGroups, notifiedUsers, showInActivityFeed, responses
        case active, createdAt, updatedAt
    }
    
    // Computed properties
    var timeRemaining: TimeInterval {
        return endTime.timeIntervalSince(Date())
    }
    
    var isExpired: Bool {
        return timeRemaining <= 0
    }
    
    var formattedTimeRemaining: String {
        let remaining = timeRemaining
        if remaining <= 0 {
            return "Ended"
        }
        
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var durationText: String {
        switch duration {
        case "30":
            return "30 minutes"
        case "60":
            return "1 hour"
        case "120":
            return "2 hours"
        case "until_leave":
            return "Until I leave"
        default:
            return duration
        }
    }
    
    var goingCount: Int {
        return responses.filter { $0.status == "going" }.count
    }
    
    var interestedCount: Int {
        return responses.filter { $0.status == "interested" }.count
    }
    
    var coordinate: CLLocationCoordinate2D? {
        return location?.coordinate
    }
}

struct CheckInLocation: Codable {
    let latitude: Double
    let longitude: Double
    
    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct CheckInResponse: Codable {
    let userId: String
    let userName: String
    let userPhoto: String?
    let status: String // "interested" or "going"
    let timestamp: Date
}