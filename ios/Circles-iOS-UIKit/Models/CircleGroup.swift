import Foundation

// MARK: - CircleGroup Model
struct CircleGroup: Codable, Identifiable {
    let id: String
    let name: String
    let circleIds: [String] // IDs of circles in this group
    let coverImages: [String?] // First 4 circle cover images for mini-grid display
    let owner: String
    let ownerDetails: User? // Populated when fetching shared groups
    let privacy: PrivacyLevel // Groups inherit most restrictive privacy of contained circles
    let createdAt: Date
    let updatedAt: Date
    let circles: [Circle]? // Populated with full circle details when needed
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, circleIds, coverImages, owner, ownerDetails, privacy
        case createdAt, updatedAt, circles
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        circleIds = try container.decode([String].self, forKey: .circleIds)
        coverImages = try container.decode([String?].self, forKey: .coverImages)
        owner = try container.decode(String.self, forKey: .owner)
        ownerDetails = try container.decodeIfPresent(User.self, forKey: .ownerDetails)
        privacy = try container.decode(PrivacyLevel.self, forKey: .privacy)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        circles = try container.decodeIfPresent([Circle].self, forKey: .circles)
    }
    
    // Manual init for creating groups in code
    init(id: String, name: String, circleIds: [String], coverImages: [String?], owner: String,
         ownerDetails: User? = nil, privacy: PrivacyLevel, createdAt: Date = Date(),
         updatedAt: Date = Date(), circles: [Circle]? = nil) {
        self.id = id
        self.name = name
        self.circleIds = circleIds
        self.coverImages = coverImages
        self.owner = owner
        self.ownerDetails = ownerDetails
        self.privacy = privacy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.circles = circles
    }
    
    // MARK: - Computed Properties
    
    /// Number of circles in this group
    var circleCount: Int {
        return circleIds.count
    }
    
    /// Whether the current user owns this group
    var isOwnedByCurrentUser: Bool {
        return owner == AuthService.shared.getUserId()
    }
    
    /// First 4 cover images for display (fills with nil if needed)
    var displayCoverImages: [String?] {
        let images = Array(coverImages.prefix(4))
        // Pad with nil values to always have 4 elements for consistent 2x2 grid
        return images + Array(repeating: nil, count: max(0, 4 - images.count))
    }
    
    /// Display text for circle count
    var circleCountText: String {
        return "\(circleCount) \(circleCount == 1 ? "circle" : "circles")"
    }
}

// MARK: - CircleGroup Extensions

extension CircleGroup {
    /// Create a group from multiple circles
    static func createFrom(circles: [Circle], name: String, owner: String) -> CircleGroup {
        let circleIds = circles.map { $0.id }
        let coverImages = circles.prefix(4).map { $0.coverImage }
        
        // Determine most restrictive privacy level
        let privacy = circles.map { $0.privacy }.max() ?? .private
        
        return CircleGroup(
            id: UUID().uuidString, // Temporary ID - will be set by backend
            name: name,
            circleIds: circleIds,
            coverImages: coverImages,
            owner: owner,
            privacy: privacy
        )
    }
    
    /// Add a circle to this group
    func addingCircle(_ circle: Circle) -> CircleGroup {
        var newCircleIds = circleIds
        var newCoverImages = coverImages
        
        // Add circle if not already present
        if !newCircleIds.contains(circle.id) {
            newCircleIds.append(circle.id)
            
            // Add cover image if we have less than 4
            if newCoverImages.count < 4 {
                newCoverImages.append(circle.coverImage)
            }
        }
        
        // Update privacy to most restrictive
        let newPrivacy = max(privacy, circle.privacy)
        
        return CircleGroup(
            id: id,
            name: name,
            circleIds: newCircleIds,
            coverImages: newCoverImages,
            owner: owner,
            ownerDetails: ownerDetails,
            privacy: newPrivacy,
            createdAt: createdAt,
            updatedAt: Date(),
            circles: circles
        )
    }
    
    /// Remove a circle from this group
    func removingCircle(withId circleId: String) -> CircleGroup? {
        var newCircleIds = circleIds.filter { $0 != circleId }
        
        // If removing this circle would leave the group empty, return nil (delete group)
        if newCircleIds.isEmpty {
            return nil
        }
        
        // Remove corresponding cover image if it exists
        if let index = circleIds.firstIndex(of: circleId), index < coverImages.count {
            var newCoverImages = coverImages
            newCoverImages.remove(at: index)
            
            return CircleGroup(
                id: id,
                name: name,
                circleIds: newCircleIds,
                coverImages: newCoverImages,
                owner: owner,
                ownerDetails: ownerDetails,
                privacy: privacy, // Keep existing privacy for now
                createdAt: createdAt,
                updatedAt: Date(),
                circles: circles
            )
        }
        
        return CircleGroup(
            id: id,
            name: name,
            circleIds: newCircleIds,
            coverImages: coverImages,
            owner: owner,
            ownerDetails: ownerDetails,
            privacy: privacy,
            createdAt: createdAt,
            updatedAt: Date(),
            circles: circles
        )
    }
}

// MARK: - API Response Models

struct CircleGroupResponse: Codable {
    let success: Bool
    let data: CircleGroup
    let message: String?
}

struct CircleGroupsResponse: Codable {
    let success: Bool
    let data: [CircleGroup]
    let message: String?
}

struct CreateCircleGroupRequest: Codable {
    let name: String
    let circleIds: [String]
}

struct UpdateCircleGroupRequest: Codable {
    let name: String?
    let circleIds: [String]?
}