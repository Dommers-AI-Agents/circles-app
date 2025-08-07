import Foundation

// MARK: - User Copy Extension
// This extension eliminates the need to specify all properties when updating a User instance

extension User {
    /// Creates a copy of the user with specified properties updated
    /// - Parameters: Only specify the properties you want to change
    func copy(
        id: String? = nil,
        email: String? = nil,
        displayName: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        phoneNumber: String? = nil,
        profilePicture: String? = nil,
        bio: String? = nil,
        location: String? = nil,
        friends: [String]? = nil,
        friendRequests: [String]? = nil,
        circleOrder: [String]? = nil,
        preferences: UserPreferences? = nil,
        createdAt: Date? = nil,
        connectionStatus: String? = nil,
        connectionDirection: String? = nil,
        connectionId: String? = nil,
        followers: [String]? = nil,
        following: [String]? = nil,
        followersCount: Int? = nil,
        followingCount: Int? = nil,
        connectionsCount: Int? = nil,
        placesCount: Int? = nil,
        pinnedPlaces: [String]? = nil,
        isFollowing: Bool? = nil,
        notificationPreferences: NotificationPreferences? = nil,
        subscriptionStatus: String? = nil,
        subscriptionExpiryDate: Date? = nil,
        trialStartDate: Date? = nil,
        trialEndDate: Date? = nil,
        referralCode: String? = nil,
        referredBy: String? = nil,
        referralCount: Int? = nil,
        referralRewards: [ReferralReward]? = nil
    ) -> User {
        return User(
            id: id ?? self.id,
            email: email ?? self.email,
            displayName: displayName ?? self.displayName,
            firstName: firstName ?? self.firstName,
            lastName: lastName ?? self.lastName,
            phoneNumber: phoneNumber ?? self.phoneNumber,
            profilePicture: profilePicture ?? self.profilePicture,
            bio: bio ?? self.bio,
            location: location ?? self.location,
            friends: friends ?? self.friends,
            friendRequests: friendRequests ?? self.friendRequests,
            circleOrder: circleOrder ?? self.circleOrder,
            preferences: preferences ?? self.preferences,
            createdAt: createdAt ?? self.createdAt,
            connectionStatus: connectionStatus ?? self.connectionStatus,
            connectionDirection: connectionDirection ?? self.connectionDirection,
            connectionId: connectionId ?? self.connectionId,
            followers: followers ?? self.followers,
            following: following ?? self.following,
            followersCount: followersCount ?? self.followersCount,
            followingCount: followingCount ?? self.followingCount,
            connectionsCount: connectionsCount ?? self.connectionsCount,
            placesCount: placesCount ?? self.placesCount,
            pinnedPlaces: pinnedPlaces ?? self.pinnedPlaces,
            isFollowing: isFollowing ?? self.isFollowing,
            notificationPreferences: notificationPreferences ?? self.notificationPreferences,
            subscriptionStatus: subscriptionStatus ?? self.subscriptionStatus,
            subscriptionExpiryDate: subscriptionExpiryDate ?? self.subscriptionExpiryDate,
            trialStartDate: trialStartDate ?? self.trialStartDate,
            trialEndDate: trialEndDate ?? self.trialEndDate,
            referralCode: referralCode ?? self.referralCode,
            referredBy: referredBy ?? self.referredBy,
            referralCount: referralCount ?? self.referralCount,
            referralRewards: referralRewards ?? self.referralRewards
        )
    }
    
    /// Convenience method for updating connection status
    func withConnectionStatus(_ status: String?, direction: String? = nil) -> User {
        return self.copy(connectionStatus: status, connectionDirection: direction)
    }
    
    /// Convenience method for updating following status
    func withFollowingStatus(_ isFollowing: Bool) -> User {
        return self.copy(isFollowing: isFollowing)
    }
    
    /// Convenience method for updating follower counts
    func withFollowerCounts(followers: Int? = nil, following: Int? = nil) -> User {
        return self.copy(
            followersCount: followers,
            followingCount: following
        )
    }
}

// Example usage:
// Instead of:
// self.user = User(id: user.id, email: user.email, ... 20+ more properties ..., connectionDirection: "outgoing")
//
// Now you can write:
// self.user = user.copy(connectionDirection: "outgoing")
// or
// self.user = user.withConnectionStatus("pending", direction: "outgoing")