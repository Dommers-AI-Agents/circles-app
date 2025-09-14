import Foundation

// MARK: - Notification Names Extension
extension Notification.Name {
    // Network notifications
    static let pendingConnectionsCountChanged = Notification.Name("PendingConnectionsCountChanged")
    static let connectionsLoaded = Notification.Name("ConnectionsLoaded")
    
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
}