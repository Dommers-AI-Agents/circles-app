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
    
    // Suggestions notifications
    static let clearSuggestionsBadge = Notification.Name("clearSuggestionsBadge")
    static let suggestionsBadgeUpdate = Notification.Name("suggestionsBadgeUpdate")
}