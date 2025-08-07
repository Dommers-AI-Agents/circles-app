import Foundation

struct UserPreferences: Codable {
    let defaultHomeView: String? // "list" or "map"
}

struct NotificationPreferences: Codable {
    var newMessages: Bool = true
    var newSuggestions: Bool = true
    var newPlaces: Bool = true
    var connectionRequests: Bool = true
    var circleInvites: Bool = true
    var newFollowers: Bool = true
    var dailyDigest: Bool = false
    
    // Daily summary settings
    var dailySummary: Bool = true
    var summaryTime: String = "12:00"
    var timezone: String = "America/New_York"
    
    // Additional notification types
    var socialActivity: Bool = true
    var discoveryPrompts: Bool = true
    var milestones: Bool = true
    var weekendRecommendations: Bool = true
    var reengagement: Bool = true
    var frequency: String = "normal" // "minimal", "normal", "all"
    
    // Quiet hours
    var quietHoursEnabled: Bool = false
    var quietHoursStart: String = "22:00"
    var quietHoursEnd: String = "08:00"
    
    // Default initializer
    init() {
        // All properties already have default values assigned above
    }
    
    // Custom decoder to handle missing fields with default values
    enum CodingKeys: String, CodingKey {
        case newMessages, newSuggestions, newPlaces, connectionRequests, circleInvites, newFollowers, dailyDigest
        case dailySummary, summaryTime, timezone
        case socialActivity, discoveryPrompts, milestones, weekendRecommendations, reengagement, frequency
        case quietHoursEnabled, quietHoursStart, quietHoursEnd
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Use decodeIfPresent with fallback to default values
        newMessages = try container.decodeIfPresent(Bool.self, forKey: .newMessages) ?? true
        newSuggestions = try container.decodeIfPresent(Bool.self, forKey: .newSuggestions) ?? true
        newPlaces = try container.decodeIfPresent(Bool.self, forKey: .newPlaces) ?? true
        connectionRequests = try container.decodeIfPresent(Bool.self, forKey: .connectionRequests) ?? true
        circleInvites = try container.decodeIfPresent(Bool.self, forKey: .circleInvites) ?? true
        newFollowers = try container.decodeIfPresent(Bool.self, forKey: .newFollowers) ?? true
        dailyDigest = try container.decodeIfPresent(Bool.self, forKey: .dailyDigest) ?? false
        
        // Daily summary settings
        dailySummary = try container.decodeIfPresent(Bool.self, forKey: .dailySummary) ?? true
        summaryTime = try container.decodeIfPresent(String.self, forKey: .summaryTime) ?? "12:00"
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? "America/New_York"
        
        // Additional notification types
        socialActivity = try container.decodeIfPresent(Bool.self, forKey: .socialActivity) ?? true
        discoveryPrompts = try container.decodeIfPresent(Bool.self, forKey: .discoveryPrompts) ?? true
        milestones = try container.decodeIfPresent(Bool.self, forKey: .milestones) ?? true
        weekendRecommendations = try container.decodeIfPresent(Bool.self, forKey: .weekendRecommendations) ?? true
        reengagement = try container.decodeIfPresent(Bool.self, forKey: .reengagement) ?? true
        frequency = try container.decodeIfPresent(String.self, forKey: .frequency) ?? "normal"
        
        // Quiet hours
        quietHoursEnabled = try container.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? false
        quietHoursStart = try container.decodeIfPresent(String.self, forKey: .quietHoursStart) ?? "22:00"
        quietHoursEnd = try container.decodeIfPresent(String.self, forKey: .quietHoursEnd) ?? "08:00"
    }
}

struct User: Codable, Identifiable {
    let id: String
    let email: String?
    let displayName: String
    let firstName: String?
    let lastName: String?
    let phoneNumber: String?
    let profilePicture: String?
    let bio: String?
    let location: String?
    let friends: [String]?
    let friendRequests: [String]?
    let circleOrder: [String]?
    let preferences: UserPreferences?
    let createdAt: Date?
    let connectionStatus: String? // "connected", "pending", or nil
    let connectionDirection: String? // "incoming" or "outgoing" for pending connections
    let connectionId: String? // ID of the connection document
    
    // Instagram-style follower system
    let followers: [String]?
    let following: [String]?
    let followersCount: Int?
    let followingCount: Int?
    
    // Connections count (LinkedIn-style professional network)
    let connectionsCount: Int?
    
    // Places count (total places across all circles)
    let placesCount: Int?
    
    // Circles count (total circles created by user)
    let circlesCount: Int?
    
    // Pinned places (max 6)
    let pinnedPlaces: [String]?
    
    // Whether the current user is following this user (for other user profiles)
    let isFollowing: Bool?
    
    // Flag to identify fake profiles for onboarding
    let isFakeProfile: Bool?
    
    // Notification preferences
    let notificationPreferences: NotificationPreferences?
    
    // Subscription fields
    let subscriptionStatus: String?
    let subscriptionExpiryDate: Date?
    let trialStartDate: Date?
    let trialEndDate: Date?
    
    // Referral fields
    let referralCode: String?
    let referredBy: String?
    let referralCount: Int
    let referralRewards: [ReferralReward]?
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case email, displayName, firstName, lastName, phoneNumber, profilePicture, bio, location, friends, friendRequests, circleOrder, preferences, createdAt, connectionStatus, connectionDirection, connectionId, followers, following, followersCount, followingCount, connectionsCount, placesCount, circlesCount, pinnedPlaces, isFollowing, isFakeProfile, notificationPreferences
        case subscriptionStatus, subscriptionExpiryDate, trialStartDate, trialEndDate
        case referralCode, referredBy, referralCount, referralRewards
    }
    
    // Convenience initializer for creating User objects directly
    public init(id: String, email: String? = nil, displayName: String, firstName: String? = nil, lastName: String? = nil, phoneNumber: String? = nil, profilePicture: String?, bio: String?, location: String?, friends: [String]?, friendRequests: [String]?, circleOrder: [String]? = nil, preferences: UserPreferences? = nil, createdAt: Date? = nil, connectionStatus: String? = nil, connectionDirection: String? = nil, connectionId: String? = nil, followers: [String]? = nil, following: [String]? = nil, followersCount: Int? = nil, followingCount: Int? = nil, connectionsCount: Int? = nil, placesCount: Int? = nil, circlesCount: Int? = nil, pinnedPlaces: [String]? = nil, isFollowing: Bool? = nil, isFakeProfile: Bool? = nil, notificationPreferences: NotificationPreferences? = nil, subscriptionStatus: String? = nil, subscriptionExpiryDate: Date? = nil, trialStartDate: Date? = nil, trialEndDate: Date? = nil, referralCode: String? = nil, referredBy: String? = nil, referralCount: Int = 0, referralRewards: [ReferralReward]? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber
        self.profilePicture = profilePicture
        self.bio = bio
        self.location = location
        self.friends = friends
        self.friendRequests = friendRequests
        self.circleOrder = circleOrder
        self.preferences = preferences
        self.createdAt = createdAt
        self.connectionStatus = connectionStatus
        self.connectionDirection = connectionDirection
        self.connectionId = connectionId
        self.followers = followers
        self.following = following
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.connectionsCount = connectionsCount
        self.placesCount = placesCount
        self.circlesCount = circlesCount
        self.pinnedPlaces = pinnedPlaces
        self.isFollowing = isFollowing
        self.isFakeProfile = isFakeProfile
        self.notificationPreferences = notificationPreferences
        self.subscriptionStatus = subscriptionStatus
        self.subscriptionExpiryDate = subscriptionExpiryDate
        self.trialStartDate = trialStartDate
        self.trialEndDate = trialEndDate
        self.referralCode = referralCode
        self.referredBy = referredBy
        self.referralCount = referralCount
        self.referralRewards = referralRewards
    }
    
    // Custom decoder for JSON decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode id with flexible field names (_id or id)
        if let id = try? container.decode(String.self, forKey: .id) {
            self.id = id
        } else {
            // Try to decode with dynamic key "id" (without underscore)
            struct DynamicCodingKeys: CodingKey {
                var stringValue: String
                var intValue: Int? { nil }
                
                init(stringValue: String) {
                    self.stringValue = stringValue
                }
                
                init?(intValue: Int) {
                    return nil
                }
            }
            
            let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKeys.self)
            if let id = try? dynamicContainer.decode(String.self, forKey: DynamicCodingKeys(stringValue: "id")) {
                self.id = id
            } else {
                throw DecodingError.keyNotFound(CodingKeys.id, 
                    DecodingError.Context(codingPath: decoder.codingPath, 
                                        debugDescription: "No value found for key '_id' or 'id'"))
            }
        }
        
        email = try container.decodeIfPresent(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        profilePicture = try container.decodeIfPresent(String.self, forKey: .profilePicture)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        friends = try container.decodeIfPresent([String].self, forKey: .friends)
        friendRequests = try container.decodeIfPresent([String].self, forKey: .friendRequests)
        circleOrder = try container.decodeIfPresent([String].self, forKey: .circleOrder)
        preferences = try container.decodeIfPresent(UserPreferences.self, forKey: .preferences)
        connectionStatus = try container.decodeIfPresent(String.self, forKey: .connectionStatus)
        connectionDirection = try container.decodeIfPresent(String.self, forKey: .connectionDirection)
        connectionId = try container.decodeIfPresent(String.self, forKey: .connectionId)
        
        // Instagram-style follower system
        followers = try container.decodeIfPresent([String].self, forKey: .followers)
        following = try container.decodeIfPresent([String].self, forKey: .following)
        followersCount = try container.decodeIfPresent(Int.self, forKey: .followersCount)
        followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount)
        
        // Connections count (LinkedIn-style professional network)
        connectionsCount = try container.decodeIfPresent(Int.self, forKey: .connectionsCount)
        
        // Places count
        placesCount = try container.decodeIfPresent(Int.self, forKey: .placesCount)
        
        // Circles count
        circlesCount = try container.decodeIfPresent(Int.self, forKey: .circlesCount)
        
        // Pinned places
        pinnedPlaces = try container.decodeIfPresent([String].self, forKey: .pinnedPlaces)
        
        // Follow status (for other user profiles)
        isFollowing = try container.decodeIfPresent(Bool.self, forKey: .isFollowing)
        
        // Fake profile flag
        isFakeProfile = try container.decodeIfPresent(Bool.self, forKey: .isFakeProfile)
        
        // Notification preferences
        notificationPreferences = try container.decodeIfPresent(NotificationPreferences.self, forKey: .notificationPreferences)
        
        // Subscription fields
        subscriptionStatus = try container.decodeIfPresent(String.self, forKey: .subscriptionStatus)
        
        // Decode subscription dates
        if let expiryDateString = try container.decodeIfPresent(String.self, forKey: .subscriptionExpiryDate) {
            subscriptionExpiryDate = ISO8601DateFormatter().date(from: expiryDateString)
        } else {
            subscriptionExpiryDate = nil
        }
        
        if let trialStartString = try container.decodeIfPresent(String.self, forKey: .trialStartDate) {
            trialStartDate = ISO8601DateFormatter().date(from: trialStartString)
        } else {
            trialStartDate = nil
        }
        
        if let trialEndString = try container.decodeIfPresent(String.self, forKey: .trialEndDate) {
            trialEndDate = ISO8601DateFormatter().date(from: trialEndString)
        } else {
            trialEndDate = nil
        }
        
        // Referral fields
        referralCode = try container.decodeIfPresent(String.self, forKey: .referralCode)
        referredBy = try container.decodeIfPresent(String.self, forKey: .referredBy)
        referralCount = try container.decodeIfPresent(Int.self, forKey: .referralCount) ?? 0
        referralRewards = try container.decodeIfPresent([ReferralReward].self, forKey: .referralRewards)
        
        // Custom date decoding with multiple format support
        if let dateString = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            if let date = formatter.date(from: dateString) {
                createdAt = date
            } else {
                // Fallback to basic ISO8601 format
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: dateString) {
                    createdAt = date
                } else {
                    createdAt = nil
                }
            }
        } else {
            createdAt = nil
        }
    }
    
    // Helper method to create a copy of the user with updated isFollowing status
    func copy(isFollowing: Bool) -> User {
        return User(
            id: self.id,
            email: self.email,
            displayName: self.displayName,
            firstName: self.firstName,
            lastName: self.lastName,
            phoneNumber: self.phoneNumber,
            profilePicture: self.profilePicture,
            bio: self.bio,
            location: self.location,
            friends: self.friends,
            friendRequests: self.friendRequests,
            circleOrder: self.circleOrder,
            preferences: self.preferences,
            createdAt: self.createdAt,
            connectionStatus: self.connectionStatus,
            connectionDirection: self.connectionDirection,
            connectionId: self.connectionId,
            followers: self.followers,
            following: self.following,
            followersCount: self.followersCount,
            followingCount: self.followingCount,
            connectionsCount: self.connectionsCount,
            placesCount: self.placesCount,
            circlesCount: self.circlesCount,
            pinnedPlaces: self.pinnedPlaces,
            isFollowing: isFollowing, // Updated value
            isFakeProfile: self.isFakeProfile,
            notificationPreferences: self.notificationPreferences,
            subscriptionStatus: self.subscriptionStatus,
            subscriptionExpiryDate: self.subscriptionExpiryDate,
            trialStartDate: self.trialStartDate,
            trialEndDate: self.trialEndDate
        )
    }
    
}
