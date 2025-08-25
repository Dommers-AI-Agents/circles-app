import Foundation
import FirebaseAnalytics

/**
 * Centralized Analytics Service for Circles App
 * 
 * This service provides a clean interface for tracking user behavior, engagement metrics,
 * and conversion events using Firebase Analytics. All analytics calls are centralized here
 * to ensure consistency and maintainability.
 *
 * Privacy Note: This service respects user privacy settings and iOS ATT framework.
 */
final class AnalyticsService {
    
    // MARK: - Singleton
    static let shared = AnalyticsService()
    
    // MARK: - Properties
    private var isEnabled = true
    private var userId: String?
    private let userDefaults = UserDefaults.standard
    
    // UserDefaults keys
    private let kAnalyticsEnabled = "analytics_enabled"
    private let kAnalyticsUserId = "analytics_user_id"
    
    // MARK: - Event Names
    struct Events {
        // Onboarding Events
        static let onboardingStarted = "onboarding_started"
        static let onboardingCompleted = "onboarding_completed"
        static let onboardingSkipped = "onboarding_skipped"
        static let tutorialViewed = "tutorial_viewed"
        
        // Authentication Events
        static let signUpStarted = "sign_up_started"
        static let signUpCompleted = "sign_up_completed"
        static let loginCompleted = "login_completed"
        static let loginFailed = "login_failed"
        static let logout = "logout"
        static let socialLoginUsed = "social_login_used"
        
        // Circle Events
        static let circleCreated = "circle_created"
        static let circleViewed = "circle_viewed"
        static let circleEdited = "circle_edited"
        static let circleDeleted = "circle_deleted"
        static let circleShared = "circle_shared"
        static let circlePrivacyChanged = "circle_privacy_changed"
        
        // Place Events
        static let placeAdded = "place_added"
        static let placeViewed = "place_viewed"
        static let placeEdited = "place_edited"
        static let placeRemoved = "place_removed"
        static let placeSearched = "place_searched"
        static let placeNoteAdded = "place_note_added"
        
        // Social Events
        static let connectionRequested = "connection_requested"
        static let connectionAccepted = "connection_accepted"
        static let connectionRejected = "connection_rejected"
        static let userFollowed = "user_followed"
        static let userUnfollowed = "user_unfollowed"
        static let profileViewed = "profile_viewed"
        
        // Engagement Events
        static let commentAdded = "comment_added"
        static let placeliked = "place_liked"
        static let circleliked = "circle_liked"
        static let suggestionSent = "suggestion_sent"
        static let suggestionViewed = "suggestion_viewed"
        static let messagesSent = "message_sent"
        static let messagesViewed = "messages_viewed"
        
        // Content Events
        static let momentCreated = "moment_created"
        static let momentViewed = "moment_viewed"
        static let videoRecorded = "video_recorded"
        static let photoTaken = "photo_taken"
        static let socialLinkAdded = "social_link_added"
        
        // Subscription Events
        static let paywallViewed = "paywall_viewed"
        static let paywallDismissed = "paywall_dismissed"
        static let subscriptionStarted = "subscription_started"
        static let subscriptionCancelled = "subscription_cancelled"
        static let subscriptionRenewed = "subscription_renewed"
        static let trialStarted = "trial_started"
        static let trialConverted = "trial_converted"
        
        // Feature Usage Events
        static let dailySummaryOpened = "daily_summary_opened"
        static let dailySummaryDismissed = "daily_summary_dismissed"
        static let notificationEnabled = "notification_enabled"
        static let notificationDisabled = "notification_disabled"
        static let searchPerformed = "search_performed"
        static let filterApplied = "filter_applied"
        static let mapViewed = "map_viewed"
        static let exportDataRequested = "export_data_requested"
        
        // App Lifecycle Events
        static let appOpened = "app_opened"
        static let sessionStarted = "session_started"
        static let sessionEnded = "session_ended"
        static let deepLinkOpened = "deep_link_opened"
    }
    
    // MARK: - User Properties
    struct UserProperties {
        static let subscriptionStatus = "subscription_status"
        static let userType = "user_type" // new, returning, premium
        static let connectionCount = "connection_count"
        static let circleCount = "circle_count"
        static let placeCount = "place_count"
        static let loginMethod = "login_method" // email, google, apple, facebook
        static let hasProfilePicture = "has_profile_picture"
        static let hasLocation = "has_location"
        static let notificationsEnabled = "notifications_enabled"
        static let accountAge = "account_age_days"
        static let lastActiveDate = "last_active_date"
    }
    
    // MARK: - Initialization
    private init() {
        self.isEnabled = userDefaults.bool(forKey: kAnalyticsEnabled)
        self.userId = userDefaults.string(forKey: kAnalyticsUserId)
        
        // Set default collection settings
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
    }
    
    // MARK: - Public Methods
    
    /**
     * Initialize analytics with user consent
     */
    func initialize(withConsent consent: Bool = true) {
        self.isEnabled = consent
        userDefaults.set(consent, forKey: kAnalyticsEnabled)
        Analytics.setAnalyticsCollectionEnabled(consent)
        
        if consent {
            print("📊 Analytics: Initialized with user consent")
        } else {
            print("📊 Analytics: Disabled per user preference")
        }
    }
    
    /**
     * Set the current user ID for analytics tracking
     */
    func setUserId(_ userId: String?) {
        self.userId = userId
        
        if let userId = userId {
            Analytics.setUserID(userId)
            userDefaults.set(userId, forKey: kAnalyticsUserId)
            print("📊 Analytics: User ID set - \(userId)")
        } else {
            Analytics.setUserID(nil)
            userDefaults.removeObject(forKey: kAnalyticsUserId)
            print("📊 Analytics: User ID cleared")
        }
    }
    
    /**
     * Set a user property for segmentation
     */
    func setUserProperty(_ value: String?, forName name: String) {
        guard isEnabled else { return }
        Analytics.setUserProperty(value, forName: name)
        print("📊 Analytics: User property set - \(name): \(value ?? "nil")")
    }
    
    /**
     * Log a custom event with optional parameters
     */
    func logEvent(_ eventName: String, parameters: [String: Any]? = nil) {
        guard isEnabled else { return }
        
        // Firebase has a 500 distinct event limit, so we use consistent naming
        let sanitizedEventName = eventName.prefix(40).lowercased().replacingOccurrences(of: " ", with: "_")
        
        Analytics.logEvent(sanitizedEventName, parameters: parameters)
        
        #if DEBUG
        print("📊 Analytics Event: \(sanitizedEventName)")
        if let params = parameters {
            print("   Parameters: \(params)")
        }
        #endif
    }
    
    // MARK: - Convenience Methods
    
    /**
     * Track user login
     */
    func trackLogin(method: String) {
        logEvent(Events.loginCompleted, parameters: [
            AnalyticsParameterMethod: method
        ])
        setUserProperty(method, forName: UserProperties.loginMethod)
    }
    
    /**
     * Track sign up
     */
    func trackSignUp(method: String) {
        logEvent(Events.signUpCompleted, parameters: [
            AnalyticsParameterMethod: method
        ])
        setUserProperty(method, forName: UserProperties.loginMethod)
    }
    
    /**
     * Track circle creation
     */
    func trackCircleCreated(privacy: String, placeCount: Int) {
        logEvent(Events.circleCreated, parameters: [
            "privacy_level": privacy,
            "initial_place_count": placeCount
        ])
    }
    
    /**
     * Track circle viewed
     */
    func trackCircleViewed(circleId: String, isOwner: Bool) {
        logEvent(Events.circleViewed, parameters: [
            "circle_id": circleId,
            "is_owner": isOwner
        ])
    }
    
    /**
     * Track place added to circle
     */
    func trackPlaceAdded(circleId: String, placeCategory: String? = nil) {
        logEvent(Events.placeAdded, parameters: [
            "circle_id": circleId,
            "place_category": placeCategory ?? "unknown"
        ])
    }
    
    /**
     * Track connection request
     */
    func trackConnectionRequest(targetUserId: String) {
        logEvent(Events.connectionRequested, parameters: [
            "target_user_id": targetUserId
        ])
    }
    
    /**
     * Track suggestion sent
     */
    func trackSuggestionSent(placeId: String, recipientCount: Int) {
        logEvent(Events.suggestionSent, parameters: [
            "place_id": placeId,
            "recipient_count": recipientCount
        ])
    }
    
    /**
     * Track subscription events
     */
    func trackPaywallViewed(trigger: String) {
        logEvent(Events.paywallViewed, parameters: [
            "trigger": trigger
        ])
    }
    
    func trackSubscriptionStarted(productId: String, price: Double) {
        logEvent(Events.subscriptionStarted, parameters: [
            AnalyticsParameterItemID: productId,
            AnalyticsParameterPrice: price,
            AnalyticsParameterCurrency: "USD"
        ])
        setUserProperty("premium", forName: UserProperties.subscriptionStatus)
    }
    
    /**
     * Track content creation
     */
    func trackMomentCreated(type: String, hasPlace: Bool) {
        logEvent(Events.momentCreated, parameters: [
            "content_type": type, // video, photo, link
            "has_place": hasPlace
        ])
    }
    
    /**
     * Track daily summary interaction
     */
    func trackDailySummaryOpened(newPlaces: Int, newConnections: Int) {
        logEvent(Events.dailySummaryOpened, parameters: [
            "new_places_count": newPlaces,
            "new_connections_count": newConnections
        ])
    }
    
    /**
     * Track search
     */
    func trackSearch(query: String, resultCount: Int, searchType: String) {
        logEvent(Events.searchPerformed, parameters: [
            AnalyticsParameterSearchTerm: query,
            "result_count": resultCount,
            "search_type": searchType // places, users, circles
        ])
    }
    
    /**
     * Update user profile properties
     */
    func updateUserProfile(connectionCount: Int, circleCount: Int, placeCount: Int) {
        setUserProperty("\(connectionCount)", forName: UserProperties.connectionCount)
        setUserProperty("\(circleCount)", forName: UserProperties.circleCount)
        setUserProperty("\(placeCount)", forName: UserProperties.placeCount)
    }
    
    /**
     * Track app opened from notification or deep link
     */
    func trackAppOpened(source: String) {
        logEvent(Events.appOpened, parameters: [
            "source": source // notification, deep_link, organic
        ])
    }
    
    /**
     * Track feature usage
     */
    func trackFeatureUsed(_ feature: String) {
        logEvent("feature_used", parameters: [
            "feature_name": feature
        ])
    }
    
    /**
     * Track error events for debugging
     */
    func trackError(_ error: Error, context: String) {
        logEvent("error_occurred", parameters: [
            "error_message": error.localizedDescription,
            "error_context": context
        ])
    }
    
    // MARK: - Screen Tracking
    
    /**
     * Track screen views (automatically handled by Firebase, but we can add custom tracking)
     */
    func trackScreenView(_ screenName: String, screenClass: String? = nil) {
        guard isEnabled else { return }
        
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screenName,
            AnalyticsParameterScreenClass: screenClass ?? screenName
        ])
        
        #if DEBUG
        print("📊 Analytics: Screen viewed - \(screenName)")
        #endif
    }
    
    // MARK: - Session Management
    
    /**
     * Start a new session
     */
    func startSession() {
        logEvent(Events.sessionStarted)
        setUserProperty(ISO8601DateFormatter().string(from: Date()), forName: UserProperties.lastActiveDate)
    }
    
    /**
     * End current session
     */
    func endSession() {
        logEvent(Events.sessionEnded)
    }
}