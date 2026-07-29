import Foundation

// MARK: - Notification Names Extension
extension Notification.Name {
    // Network notifications
    static let pendingConnectionsCountChanged = Notification.Name("PendingConnectionsCountChanged")
    static let connectionsLoaded = Notification.Name("ConnectionsLoaded")
    /// Asks the Network tab to switch to its Discover segment. Posted by child
    /// lists that want to hand off rather than push a duplicate screen.
    static let showDiscoverSegment = Notification.Name("ShowDiscoverSegment")
    /// Asks the Network tab to switch to its Requests segment (e.g. tapping a
    /// connection-request notification).
    static let showRequestsSegment = Notification.Name("ShowRequestsSegment")
    
    // Message notifications
    static let unreadMessagesCountChanged = Notification.Name("UnreadMessagesCountChanged")
    
    // Navigation notifications
    static let navigateToMessages = Notification.Name("NavigateToMessages")
    static let navigateToNetwork = Notification.Name("NavigateToNetwork")
    static let navigateToCircle = Notification.Name("NavigateToCircle")
    static let navigateToSuggestions = Notification.Name("NavigateToSuggestions")
    static let navigateToActivity = Notification.Name("NavigateToActivity")
    static let navigateToPlace = Notification.Name("NavigateToPlace")
    static let navigateToConversation = Notification.Name("NavigateToConversation")
    static let navigateToDailySummary = Notification.Name("NavigateToDailySummary")
    
    // Suggestions notifications
    static let clearSuggestionsBadge = Notification.Name("clearSuggestionsBadge")
    static let suggestionsBadgeUpdate = Notification.Name("suggestionsBadgeUpdate")

    // Rewards notifications
    static let rewardBalanceChanged = Notification.Name("RewardBalanceChanged")

    /// Premium entitlement resolved or changed. Posted on the main thread by
    /// SubscriptionService whenever `subscriptionStatus` actually changes —
    /// status starts `.none` and resolves asynchronously, so any UI that gates
    /// on premium must rebuild on this rather than reading the value once.
    static let subscriptionStatusChanged = Notification.Name("SubscriptionStatusChanged")
}