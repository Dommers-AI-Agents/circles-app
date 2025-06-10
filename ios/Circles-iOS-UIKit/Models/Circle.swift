import Foundation

struct Circle: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let coverImage: String?
    let owner: String
    let places: [String]?
    let privacy: PrivacyLevel
    let category: CircleCategory
    let location: String?
    let tags: [String]?
    let sharedWith: [String]?
    let followers: [String]?
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, description, coverImage, owner, places, privacy, category
        case location, tags, sharedWith, followers, createdAt, updatedAt
    }
}

enum PrivacyLevel: String, Codable {
    case `public`
    case friends
    case `private`
}

enum CircleCategory: String, Codable {
    case travel
    case food
    case services
    case shopping
    case healthcare
    case entertainment
    case other
    
    var displayName: String {
        switch self {
        case .travel: return "Travel"
        case .food: return "Food & Dining"
        case .services: return "Services"
        case .shopping: return "Shopping"
        case .healthcare: return "Healthcare"
        case .entertainment: return "Entertainment"
        case .other: return "Other"
        }
    }
}
