import Foundation

// MARK: - Notification Names Extension
extension Notification.Name {
    // Network notifications
    static let pendingConnectionsCountChanged = Notification.Name("PendingConnectionsCountChanged")
    static let connectionsLoaded = Notification.Name("ConnectionsLoaded")
    /// A check-in was created (userInfo: "placeId", "globalPlaceId" when known).
    /// Place pages refresh their check-in history line on it.
    static let checkInCreated = Notification.Name("CheckInCreated")
    /// A store's shared details changed in Manage Store → Store details
    /// (userInfo "globalPlaceId"); its place page re-reads them
    static let storeDetailsChanged = Notification.Name("StoreDetailsChanged")
    /// The viewer changed their rating of a place (userInfo: "placeId", "place").
    static let placeRatingChanged = Notification.Name("PlaceRatingChanged")
    /// Asks the Network tab to switch to its Discover segment. Posted by child
    /// lists that want to hand off rather than push a duplicate screen.
    static let showDiscoverSegment = Notification.Name("ShowDiscoverSegment")
    /// Asks the Network tab to switch to its Requests segment (e.g. tapping a
    /// connection-request notification).
    static let showRequestsSegment = Notification.Name("ShowRequestsSegment")
    
    // Message notifications
    static let unreadMessagesCountChanged = Notification.Name("UnreadMessagesCountChanged")

    /// Notifications were all marked read (user opened the Notifications screen)
    /// — the home bell's unseen dot should refresh/clear immediately rather than
    /// wait for the next viewWillAppear and possibly race the read-all write.
    static let notificationsMarkedRead = Notification.Name("NotificationsMarkedRead")
    /// Some bell rows were settled by opening what they're about — re-read the red dot
    static let notificationOriginSeen = Notification.Name("NotificationOriginSeen")

    // Store-owner notifications
    /// Pending ownership claims were reviewed (approved/denied) — refresh the
    /// Me-tab badge and any storefront claim dots.
    static let storeClaimsChanged = Notification.Name("StoreClaimsChanged")
    
    // Navigation notifications
    static let navigateToMessages = Notification.Name("NavigateToMessages")
    static let navigateToNetwork = Notification.Name("NavigateToNetwork")
    static let navigateToCircle = Notification.Name("NavigateToCircle")
    static let navigateToSuggestions = Notification.Name("NavigateToSuggestions")
    static let navigateToActivity = Notification.Name("NavigateToActivity")
    static let navigateToPlace = Notification.Name("NavigateToPlace")
    static let navigateToConversation = Notification.Name("NavigateToConversation")
    static let navigateToDailySummary = Notification.Name("NavigateToDailySummary")
    /// Engagement-tip deep links (observed in CirclesTabBarController).
    static let navigateToAllPlacesMap = Notification.Name("NavigateToAllPlacesMap")
    static let navigateToCreateWallet = Notification.Name("NavigateToCreateWallet")
    /// object = widget id (e.g. "nextbar"); opens the home Widgets segment on that widget
    static let navigateToHomeWidget = Notification.Name("NavigateToHomeWidget")
    /// object = order id: the customer's order-ahead order (its status)
    static let navigateToStoreOrder = Notification.Name("NavigateToStoreOrder")
    /// object = venue id: the store's Orders screen (a new order came in)
    static let navigateToVenueOrders = Notification.Name("NavigateToVenueOrders")
    /// object = widget id; a push for that widget arrived while the app was
    /// open, so its data should be refetched rather than shown stale.
    static let refreshHomeWidget = Notification.Name("RefreshHomeWidget")
    /// "You're near <saved place>" banner tap: open the check-in sheet with
    /// that place pre-filled. `object` is the place id.
    static let navigateToCheckIn = Notification.Name("NavigateToCheckIn")
    
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

    /// The Inner Circle list changed. Privacy pickers listen so their caption
    /// ("3 people · Edit list") stays true while a form is open.
    static let innerCircleDidChange = Notification.Name("innerCircleDidChange")

    /// Posted on the main queue when the path changes between reachable and
    /// not (never for every path update). Queues drain on the way back up;
    /// the offline banner shows on the way down.
    static let networkReachabilityDidChange = Notification.Name("NetworkReachabilityDidChange")

    /// Two accounts became one and the session may now be a different user;
    /// screens holding per-user data reload.
    static let accountDidMerge = Notification.Name("AccountDidMerge")

    /// A scan or a typed code may have changed the user's store points.
    /// Screens showing a balance refetch.
    static let rewardPointsDidChange = Notification.Name("rewardPointsDidChange")

    /// Posted when a promoted purchase requires user login
    static let promotedPurchaseRequiresLogin = Notification.Name("PromotedPurchaseRequiresLogin")
    
    /// Posted when a promoted purchase is attempted but user is already subscribed
    static let promotedPurchaseAlreadySubscribed = Notification.Name("PromotedPurchaseAlreadySubscribed")
    
    /// Posted when a promoted purchase should be processed
    static let processPromotedPurchase = Notification.Name("ProcessPromotedPurchase")

    static let connectionRequestSent = Notification.Name("connectionRequestSent")

    static let circleDeleted = Notification.Name("circleDeleted")

    static let userBlocked = Notification.Name("userBlocked")
    static let userUnblocked = Notification.Name("userUnblocked")

    /// Armed the first time a store code earns points; Home then points at
    /// its $ button once: "all your reward points live here".
    static let rewardsHintArmed = Notification.Name("RewardsHintArmed")

    /// A map origin (in-app / photos / an import) was shown or hidden.
    static let mapOriginVisibilityChanged = Notification.Name("MapOriginVisibilityChanged")

    /// A store order was placed or changed status; order lists refetch.
    static let venueOrdersChanged = Notification.Name("VenueOrdersChanged")

    // Formerly inline Notification.Name("…") literals (same raw strings)
    static let connectionPickerDropdownHidden = Notification.Name("ConnectionPickerDropdownHidden")
    static let connectionPickerDropdownShown = Notification.Name("ConnectionPickerDropdownShown")
    static let connectionsChanged = Notification.Name("ConnectionsChanged")
    static let conversationDeleted = Notification.Name("ConversationDeleted")
    static let conversationUpdated = Notification.Name("ConversationUpdated")
    static let conversationsUpdated = Notification.Name("ConversationsUpdated")
    static let momentDeleted = Notification.Name("MomentDeleted")
    static let momentUploaded = Notification.Name("MomentUploaded")
    static let navigateToHome = Notification.Name("NavigateToHome")
    static let navigateToPiggyBank = Notification.Name("NavigateToPiggyBank")
    static let newMessagesReceived = Notification.Name("NewMessagesReceived")
    static let openConversationById = Notification.Name("OpenConversationById")
    static let placeAdded = Notification.Name("PlaceAdded")
    static let placeAddedToCircle = Notification.Name("PlaceAddedToCircle")
    static let placeDeleted = Notification.Name("PlaceDeleted")
    static let placeUpdated = Notification.Name("PlaceUpdated")
    static let refreshCircles = Notification.Name("RefreshCircles")
    static let savePlaceToCircle = Notification.Name("SavePlaceToCircle")
    static let showLoginForPromotedPurchase = Notification.Name("ShowLoginForPromotedPurchase")
    static let showOnboardingTour = Notification.Name("ShowOnboardingTour")
    static let showPlaceDetails = Notification.Name("ShowPlaceDetails")
    static let videoEngagementUpdate = Notification.Name("VideoEngagementUpdate")
    static let visitHistoryCleared = Notification.Name("VisitHistoryCleared")
}
