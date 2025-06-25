import Foundation

enum ShareType: String, Codable {
    case registeredUser = "registered_user"
    case email
    case link
    
    var displayName: String {
        switch self {
        case .registeredUser: return "Circles User"
        case .email: return "Email Invite"
        case .link: return "Shared Link"
        }
    }
    
    var icon: String {
        switch self {
        case .registeredUser: return "person.circle.fill"
        case .email: return "envelope.circle.fill"
        case .link: return "link.circle.fill"
        }
    }
}

enum AccessLevel: String, Codable {
    case viewOnly = "view_only"
    case canAddPlaces = "can_add_places"
    case canEdit = "can_edit"
    
    var displayName: String {
        switch self {
        case .viewOnly: return "View Only"
        case .canAddPlaces: return "Can Add Places"
        case .canEdit: return "Can Edit"
        }
    }
    
    var description: String {
        switch self {
        case .viewOnly: return "Can view circle and places"
        case .canAddPlaces: return "Can view and add new places"
        case .canEdit: return "Full edit access"
        }
    }
}

struct CircleShare: Codable, Identifiable {
    let id: String
    let circleId: String
    let circle: Circle? // Populated when needed
    let sharedBy: String // User ID who shared
    let sharedByUser: User? // Populated when fetching
    let sharedWith: String? // User ID if registered user, email if guest
    let sharedWithUser: User? // Populated if registered user
    let shareType: ShareType
    let accessLevel: AccessLevel
    let shareLink: String? // For link shares
    let expiresAt: Date?
    let lastAccessedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case circleId, circle, sharedBy, sharedByUser
        case sharedWith, sharedWithUser, shareType
        case accessLevel, shareLink, expiresAt
        case lastAccessedAt, createdAt, updatedAt
    }
    
    // Helper computed properties
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }
    
    var displayName: String {
        if let user = sharedWithUser {
            return user.displayName
        } else if let email = sharedWith, shareType == .email {
            return email
        } else if shareType == .link {
            return "Public Link"
        }
        return "Unknown"
    }
    
    var hasBeenAccessed: Bool {
        return lastAccessedAt != nil
    }
}

// Share settings for a circle
struct ShareSettings: Codable {
    let allowGuestShares: Bool
    let defaultAccessLevel: AccessLevel
    let requireApproval: Bool
    let maxShareDuration: Int? // Days
    let allowReshare: Bool
    
    init(
        allowGuestShares: Bool = true,
        defaultAccessLevel: AccessLevel = .viewOnly,
        requireApproval: Bool = false,
        maxShareDuration: Int? = nil,
        allowReshare: Bool = false
    ) {
        self.allowGuestShares = allowGuestShares
        self.defaultAccessLevel = defaultAccessLevel
        self.requireApproval = requireApproval
        self.maxShareDuration = maxShareDuration
        self.allowReshare = allowReshare
    }
}