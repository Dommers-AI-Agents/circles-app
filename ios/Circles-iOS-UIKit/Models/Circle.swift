import Foundation

struct Circle: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let coverImage: String?
    let owner: String
    let ownerDetails: User? // Populated when fetching shared circles
    let places: [String]?
    let placesWithDetails: [Place]? // Populated with full place details including who added them
    let privacy: PrivacyLevel
    let allowNetworkEdit: Bool? // Allow network connections to edit this circle
    let category: CircleCategory
    let location: String?
    let tags: [String]?
    let sharedWith: [String]?
    let followers: [String]?
    let activeShareIds: [String]? // Changed to handle string array from API
    let activeShares: [CircleShare]? // Full share objects when populated
    let shareSettings: ShareSettings?
    let isSharedWithMe: Bool? // True if this circle is shared with the current user
    let sharedBy: User? // Who shared this circle with me
    let myAccessLevel: AccessLevel? // My access level if this is a shared circle
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, description, coverImage, owner, ownerDetails
        case places, placesWithDetails, privacy, allowNetworkEdit, category
        case location, tags, sharedWith, followers, activeShares, shareSettings
        case isSharedWithMe, sharedBy, myAccessLevel
        case createdAt, updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        coverImage = try container.decodeIfPresent(String.self, forKey: .coverImage)
        owner = try container.decode(String.self, forKey: .owner)
        ownerDetails = try container.decodeIfPresent(User.self, forKey: .ownerDetails)
        places = try container.decodeIfPresent([String].self, forKey: .places)
        placesWithDetails = try container.decodeIfPresent([Place].self, forKey: .placesWithDetails)
        privacy = try container.decode(PrivacyLevel.self, forKey: .privacy)
        allowNetworkEdit = try container.decodeIfPresent(Bool.self, forKey: .allowNetworkEdit)
        category = try container.decode(CircleCategory.self, forKey: .category)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        sharedWith = try container.decodeIfPresent([String].self, forKey: .sharedWith)
        followers = try container.decodeIfPresent([String].self, forKey: .followers)
        
        // Handle activeShares - can be either array of strings or array of CircleShare objects
        if let shareObjects = try? container.decodeIfPresent([CircleShare].self, forKey: .activeShares) {
            activeShares = shareObjects
            activeShareIds = shareObjects.map { $0.id }
        } else if let shareIds = try? container.decodeIfPresent([String].self, forKey: .activeShares) {
            activeShareIds = shareIds
            activeShares = nil
        } else {
            activeShareIds = nil
            activeShares = nil
        }
        
        shareSettings = try container.decodeIfPresent(ShareSettings.self, forKey: .shareSettings)
        isSharedWithMe = try container.decodeIfPresent(Bool.self, forKey: .isSharedWithMe)
        sharedBy = try container.decodeIfPresent(User.self, forKey: .sharedBy)
        myAccessLevel = try container.decodeIfPresent(AccessLevel.self, forKey: .myAccessLevel)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    // Add manual init for creating circles in code
    init(id: String, name: String, description: String?, coverImage: String?, owner: String,
         ownerDetails: User?, places: [String]?, placesWithDetails: [Place]?,
         privacy: PrivacyLevel, allowNetworkEdit: Bool?, category: CircleCategory, location: String?,
         tags: [String]?, sharedWith: [String]?, followers: [String]?,
         activeShares: [CircleShare]?, shareSettings: ShareSettings?,
         isSharedWithMe: Bool?, sharedBy: User?, myAccessLevel: AccessLevel?,
         createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.description = description
        self.coverImage = coverImage
        self.owner = owner
        self.ownerDetails = ownerDetails
        self.places = places
        self.placesWithDetails = placesWithDetails
        self.privacy = privacy
        self.allowNetworkEdit = allowNetworkEdit
        self.category = category
        self.location = location
        self.tags = tags
        self.sharedWith = sharedWith
        self.followers = followers
        self.activeShares = activeShares
        self.activeShareIds = activeShares?.map { $0.id }
        self.shareSettings = shareSettings
        self.isSharedWithMe = isSharedWithMe
        self.sharedBy = sharedBy
        self.myAccessLevel = myAccessLevel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Helper computed properties
    var shareCount: Int {
        return activeShareIds?.count ?? activeShares?.count ?? 0
    }
    
    var hasActiveShares: Bool {
        return shareCount > 0
    }
    
    var isOwner: Bool {
        return owner == AuthService.shared.getUserId()
    }
    
    var canEdit: Bool {
        if isOwner {
            return true
        }
        return myAccessLevel == .canEdit
    }
    
    var canAddPlaces: Bool {
        if isOwner {
            return true
        }
        return myAccessLevel == .canAddPlaces || myAccessLevel == .canEdit
    }
    
    var displayOwnerName: String {
        if isOwner {
            return "You"
        } else if let ownerDetails = ownerDetails {
            return ownerDetails.displayName
        } else if let sharedBy = sharedBy {
            return sharedBy.displayName
        }
        return "Unknown"
    }
}

enum PrivacyLevel: String, Codable {
    case `public`
    case myNetwork
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
