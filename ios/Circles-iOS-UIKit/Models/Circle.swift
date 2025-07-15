import Foundation

struct Circle: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let coverImage: String?
    let owner: String
    let ownerDetails: User? // Populated when fetching shared circles
    let editors: [String]? // Array of user IDs who can edit
    let editorsDetails: [User]? // Full user objects when populated
    let places: [String]?
    let placesCount: Int? // Efficient count of places without loading them all
    let placesWithDetails: [Place]? // Populated with full place details including who added them
    let privacy: PrivacyLevel
    let allowNetworkEdit: Bool? // Allow network connections to edit this circle
    let category: CircleCategory
    let customCategoryId: String? // Reference to user's custom category
    let location: String?
    let tags: [String]?
    let sharedWith: [String]?
    let followers: [String]?
    let activeShares: [CircleShare]? // Full share objects when populated
    var activeShareIds: [String]? { // Computed property derived from activeShares
        return activeShares?.map { $0.id }
    }
    let shareSettings: ShareSettings?
    let isSharedWithMe: Bool? // True if this circle is shared with the current user
    let sharedBy: User? // Who shared this circle with me
    let myAccessLevel: AccessLevel? // My access level if this is a shared circle
    let createdAt: Date
    let updatedAt: Date
    var isNew: Bool? // Indicates if this is new activity
    var hasNewPlaces: Bool? // Indicates if circle has new places since last login
    var newPlacesCount: Int? // Number of new places since last login
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, description, coverImage, owner, ownerDetails
        case editors, editorsDetails
        case places, placesCount, placesWithDetails, privacy, allowNetworkEdit, category, customCategoryId
        case location, tags, sharedWith, followers, activeShares, shareSettings
        case isSharedWithMe, sharedBy, myAccessLevel
        case createdAt, updatedAt, isNew, hasNewPlaces, newPlacesCount
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        coverImage = try container.decodeIfPresent(String.self, forKey: .coverImage)
        owner = try container.decode(String.self, forKey: .owner)
        ownerDetails = try container.decodeIfPresent(User.self, forKey: .ownerDetails)
        editors = try container.decodeIfPresent([String].self, forKey: .editors)
        editorsDetails = try container.decodeIfPresent([User].self, forKey: .editorsDetails)
        places = try container.decodeIfPresent([String].self, forKey: .places)
        placesCount = try container.decodeIfPresent(Int.self, forKey: .placesCount)
        placesWithDetails = try container.decodeIfPresent([Place].self, forKey: .placesWithDetails)
        privacy = try container.decode(PrivacyLevel.self, forKey: .privacy)
        allowNetworkEdit = try container.decodeIfPresent(Bool.self, forKey: .allowNetworkEdit)
        category = try container.decode(CircleCategory.self, forKey: .category)
        customCategoryId = try container.decodeIfPresent(String.self, forKey: .customCategoryId)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        sharedWith = try container.decodeIfPresent([String].self, forKey: .sharedWith)
        followers = try container.decodeIfPresent([String].self, forKey: .followers)
        
        // Handle activeShares - can be either array of strings or array of CircleShare objects
        if let shareObjects = try? container.decodeIfPresent([CircleShare].self, forKey: .activeShares) {
            activeShares = shareObjects
        } else {
            // If we can't decode as CircleShare objects, just set to nil
            // The activeShareIds computed property will also be nil in this case
            activeShares = nil
        }
        
        shareSettings = try container.decodeIfPresent(ShareSettings.self, forKey: .shareSettings)
        isSharedWithMe = try container.decodeIfPresent(Bool.self, forKey: .isSharedWithMe)
        sharedBy = try container.decodeIfPresent(User.self, forKey: .sharedBy)
        myAccessLevel = try container.decodeIfPresent(AccessLevel.self, forKey: .myAccessLevel)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew)
        hasNewPlaces = try container.decodeIfPresent(Bool.self, forKey: .hasNewPlaces)
        newPlacesCount = try container.decodeIfPresent(Int.self, forKey: .newPlacesCount)
    }
    
    // Add manual init for creating circles in code
    init(id: String, name: String, description: String?, coverImage: String?, owner: String,
         ownerDetails: User?, editors: [String]?, editorsDetails: [User]?,
         places: [String]?, placesCount: Int?, placesWithDetails: [Place]?,
         privacy: PrivacyLevel, allowNetworkEdit: Bool?, category: CircleCategory, customCategoryId: String? = nil, location: String?,
         tags: [String]?, sharedWith: [String]?, followers: [String]?,
         activeShares: [CircleShare]?, shareSettings: ShareSettings?,
         isSharedWithMe: Bool?, sharedBy: User?, myAccessLevel: AccessLevel?,
         createdAt: Date, updatedAt: Date, isNew: Bool? = nil,
         hasNewPlaces: Bool? = nil, newPlacesCount: Int? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.coverImage = coverImage
        self.owner = owner
        self.ownerDetails = ownerDetails
        self.editors = editors
        self.editorsDetails = editorsDetails
        self.places = places
        self.placesCount = placesCount
        self.placesWithDetails = placesWithDetails
        self.privacy = privacy
        self.allowNetworkEdit = allowNetworkEdit
        self.category = category
        self.customCategoryId = customCategoryId
        self.location = location
        self.tags = tags
        self.sharedWith = sharedWith
        self.followers = followers
        self.activeShares = activeShares
        self.shareSettings = shareSettings
        self.isSharedWithMe = isSharedWithMe
        self.sharedBy = sharedBy
        self.myAccessLevel = myAccessLevel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isNew = isNew
        self.hasNewPlaces = hasNewPlaces
        self.newPlacesCount = newPlacesCount
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
        // Check if user is an editor
        if let userId = AuthService.shared.getUserId(),
           let editors = editors,
           editors.contains(userId) {
            return true
        }
        return myAccessLevel == .canEdit
    }
    
    var canAddPlaces: Bool {
        if isOwner {
            return true
        }
        // Check if user is an editor
        if let userId = AuthService.shared.getUserId(),
           let editors = editors,
           editors.contains(userId) {
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
