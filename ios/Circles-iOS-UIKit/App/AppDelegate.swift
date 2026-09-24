//
//  AppDelegate.swift
//  Circles-iOS-UIKit
//
//  Created by Wesley Sgroi on 5/17/25.
//

import UIKit
import FavWidgetsCore
import AuthenticationServices
import GoogleSignIn
import FacebookCore
import GooglePlaces
// Crash reporting: activates automatically inside FirebaseApp.configure().
// Added 2026-08-17 after launch-night "the app kept crashing" reports were
// undiagnosable — from this build on, crashes have stack traces.
import FirebaseCrashlytics
import Firebase
import FirebaseMessaging
import UserNotifications
import StoreKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    // Used to store Apple Sign-In credentials for an extended period
    var appleIDCompletionHandler: ((ASAuthorization?, Error?) -> Void)?
    
    // Keep track of ASAuthorizationController to prevent it from being deallocated
    var authorizationController: ASAuthorizationController?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Logger.debug("🚀 DAILY SUMMARY VERSION: App launched with enhanced notification handling - v2025.8.1-fixed")
        // Override point for customization after application launch.
        
        // Suppress Google Maps SDK duplicate class warnings in debug builds
        #if DEBUG
        UserDefaults.standard.set(false, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
        #endif
        
        // Configure Firebase first
        FirebaseApp.configure()
        
        // Initialize Analytics Service
        AnalyticsService.shared.initialize(withConsent: true)
        AnalyticsService.shared.startSession()
        
        // Configure Firebase Messaging
        Messaging.messaging().delegate = self
        
        // Get FCM token if available
        Logger.debug("🔔 ===== PUSH NOTIFICATION SETUP =====")
        Logger.debug("🔔 App launched at: \(Date())")
        Logger.debug("🔔 Requesting FCM token on app launch...")
        
        Messaging.messaging().token { token, error in
            if let error = error {
                Logger.debug("🔔 ❌ Error fetching FCM registration token: \(error)")
                Logger.debug("🔔 Error domain: \(error._domain)")
                Logger.debug("🔔 Error code: \(error._code)")
            } else if let token = token {
                Logger.debug("🔔 ✅ FCM registration token retrieved on launch")
                Logger.debug("🔔 Token length: \(token.count) characters")
                Logger.debug("🔔 Token preview: \(token.prefix(20))...")
                
                // Save to UserDefaults
                UserDefaults.standard.set(token, forKey: "FCMToken")
                UserDefaults.standard.synchronize()
                Logger.debug("🔔 Token saved to UserDefaults")
                
                // Send to backend if user is logged in
                if AuthService.shared.isLoggedIn {
                    Logger.debug("🔔 User is logged in on launch, registering token with backend")
                    Logger.debug("🔔 Backend URL: \(APIEnvironment.current.baseURL)")
                    NotificationService.shared.registerDeviceToken(token)
                } else {
                    Logger.debug("🔔 User not logged in on launch, token saved for later registration")
                }
            } else {
                Logger.debug("🔔 ⚠️ No FCM token available on launch")
            }
        }
        
        // Note: AuthManager removed - using AuthService directly
        
        // Initialize media cache and cleanup expired content
        DispatchQueue.global(qos: .background).async {
            Logger.debug("🧹 Starting media cache cleanup...")
            MediaCacheService.shared.cleanupExpiredCache()
            
            // Clear potentially corrupted activity feed image caches
            Logger.debug("🧹 Clearing activity feed image caches to fix corruption...")
            ImageService.shared.clearActivityFeedCaches()
            
            let stats = MediaCacheService.shared.getCacheStatistics()
            Logger.debug("📊 Media Cache Statistics:")
            Logger.debug("   - Total items: \(stats.itemCount)")
            Logger.debug("   - Total size: \(stats.totalSize / 1024 / 1024)MB")
            Logger.debug("   - User content: \(stats.userContentSize / 1024 / 1024)MB")
            Logger.debug("   - Network content: \(stats.networkContentSize / 1024 / 1024)MB")
        }
        
        // Configure NetworkManager after Firebase is initialized
        NetworkManager.shared.configure()
        
        // Clear any pending API requests from previous session
        APIService.shared.clearPendingRequests()
        
        // Start SSE service for real-time updates
        SSEService.shared.connect()
        
        // Initialize Visit Detection Service
        VisitDetectionService.shared.configure()

        // Nearby check-in banners are off app-wide; clear any regions a
        // previous build registered so nothing fires from a closed app.
        if !ProximityNotificationScheduler.bannersAvailable {
            ProximityNotificationScheduler.shared.cancelAll()
        }
        // Always-location users: the stop-detecting version. No-op for
        // everyone else. Also the hook for an iOS relaunch on a region event.
        DwellCheckInMonitor.shared.start()
        Logger.debug("📍 Visit Detection Service initialized")
        
        // Set up Apple ID credential state observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didChangeAuthState),
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
        
        // Configure Google Sign-In using configuration from GoogleService-Info.plist
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String,
              let reversedClientId = plist["REVERSED_CLIENT_ID"] as? String else {
            Logger.debug("❌ Failed to load Google configuration from GoogleService-Info.plist")
            return true
        }
        
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        
        // Verify URL scheme - IMPORTANT for Google Sign-In to work
        var hasRequiredScheme = false
        let requiredScheme = reversedClientId
        
        if let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] {
            for urlType in urlTypes {
                if let urlSchemes = urlType["CFBundleURLSchemes"] as? [String] {
                    hasRequiredScheme = urlSchemes.contains(requiredScheme)
                    if hasRequiredScheme { break }
                }
            }
        }
        
        if !hasRequiredScheme {
            Logger.debug("⚠️ WARNING: Required Google Sign-In URL scheme not found")
        }
        
        // Try to restore previous Google Sign-In session
        // Note: The SDK automatically manages session persistence in newer versions
        
        // Initialize Facebook SDK asynchronously to avoid blocking startup
        DispatchQueue.global(qos: .background).async {
            Logger.debug("📘 Initializing Facebook SDK in background")
            ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        }
        
        // Initialize Google Places SDK using API_KEY from GoogleService-Info.plist
        if let gmsApiKey = plist["API_KEY"] as? String {
            GMSPlacesClient.provideAPIKey(gmsApiKey)
            Logger.debug("📍 Google Places SDK initialized (photos only)")
        } else {
            Logger.debug("❌ Failed to load Google Places API key")
        }
        
        // Initialize Subscription Service
        Logger.debug("💎 Initializing Subscription Service")
        Task {
            await SubscriptionManager.shared.initialize()
        }
        
        // Start observing for promoted purchases
        Logger.debug("💎 Starting StoreKit Observer for promoted purchases")
        StoreKitObserver.shared.startObserving()
        
        // Configure Push Notifications
        Logger.debug("🔔 Configuring Push Notifications")
        UNUserNotificationCenter.current().delegate = self
        
        // Configure notification categories for rich interactions
        configureNotificationCategories()
        
        // Don't request permissions automatically - wait for user context
        // The app will prompt at appropriate times using NotificationPromptManager
        
        // Still register for remote notifications to get device token
        // This is safe to call even without permission
        application.registerForRemoteNotifications()
        
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Stop observing payment queue
        StoreKitObserver.shared.stopObserving()
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
    
    // MARK: - URL Handling for External Authentication
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Handle URL schemes for authentication services
        Logger.debug("📱 URL received in AppDelegate: \(url)")

        // Check if the URL is for Apple Sign-In
        if url.absoluteString.contains("appleid") {
            Logger.debug("🍎 Handling Apple Sign-In callback URL")
            // Note: Apple Sign-In is typically handled through the ASAuthorizationController delegate methods,
            // not through URL schemes. But we'll log it anyway.
            return true
        }
        
        // Try to handle with Google Sign-In SDK
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        
        // Handle Facebook SDK
        let facebookHandled = ApplicationDelegate.shared.application(app, open: url, options: options)
        Logger.debug("📘 Facebook SDK handling result: \(facebookHandled)")
        
        if facebookHandled {
            Logger.debug("📘 Facebook SDK successfully handled URL")
            return true
        }
        
        // Handle LinkedIn OAuth callback
        // URL format: com.favcircles.circles://linkedin/callback?code=xxx&state=yyy
        if url.scheme == "com.favcircles.circles" {
            Logger.debug("🔗 Checking if LinkedIn callback - URL: \(url.absoluteString)")
            Logger.debug("🔗 URL host: \(url.host ?? "nil"), path: \(url.path)")
            
            // Check if this is a LinkedIn callback
            if url.absoluteString.contains("linkedin") {
                Logger.debug("🔗 LinkedIn OAuth callback received")
                let handled = SocialAuthService.shared.handleLinkedInCallback(url: url)
                return handled
            }
        }
        
        // Handle other URL schemes your app may use
        Logger.debug("📱 URL not recognized by auth providers, checking app's deep linking")
        
        // Forward deep links to the active scene
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let sceneDelegate = windowScene.delegate as? SceneDelegate {
            Logger.debug("📱 Forwarding URL to SceneDelegate for deep link handling")
            sceneDelegate.handleURLContext(url)
        }
        
        return true
    }
    
    // MARK: - Continue Apple Sign-In
    
    @objc func didChangeAuthState(_ notification: Notification) {
        Logger.debug("🍎 Apple ID credential state changed")
        // Handle sign-out when Apple ID is revoked
        AuthService.shared.logout { _ in
            // This will trigger the auth state listener in SceneDelegate
        }
    }
    
    // MARK: - Background Tasks
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Logger.debug("📍 Background fetch triggered")
        
        // Sync any pending visits
        VisitDetectionService.shared.syncPendingVisits()
        
        // Complete with new data status
        completionHandler(.newData)
    }
    
    // MARK: - Push Notification Methods
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        Logger.debug("🔔 ===== APNS REGISTRATION SUCCESS =====")
        Logger.debug("🔔 APNs Device Token: \(token)")
        Logger.debug("🔔 Token length: \(token.count) characters")
        
        // Set APNs token for Firebase Messaging
        Logger.debug("🔔 Setting APNs token for Firebase Messaging...")
        Messaging.messaging().apnsToken = deviceToken
        Logger.debug("🔔 APNs token set, waiting for FCM token...")
        
        // The FCM token will be received in the MessagingDelegate callback
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger.debug("🔔 Failed to register for remote notifications: \(error)")
    }
    
    // MARK: - Background Notification Handling
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Logger.debug("🔔 Received remote notification in background/terminated state")
        Logger.debug("🔔 UserInfo: \(userInfo)")
        
        // Process the notification
        if let aps = userInfo["aps"] as? [String: Any] {
            // Update badge count if provided
            if let badge = aps["badge"] as? Int {
                UIApplication.shared.applicationIconBadgeNumber = badge
            }
            
            // Handle different notification types
            if let type = userInfo["type"] as? String {
                switch type {
                case "new_message":
                    // Update unread message count
                    MessagingManager.shared.updateUnreadCount()
                    completionHandler(.newData)
                    
                case "connection_request", "connection_accepted":
                    // Update network badge by reloading connections
                    NetworkManager.shared.loadConnections()
                    completionHandler(.newData)
                    
                case "new_place", "place_like", "place_comment", "circle_liked", "circle_commented":
                    // These might trigger activity feed updates
                    completionHandler(.newData)
                    
                default:
                    completionHandler(.noData)
                }
            } else {
                completionHandler(.noData)
            }
        } else {
            completionHandler(.noData)
        }
    }
    
    // MARK: - Notification Configuration

    private func configureNotificationCategories() {
        NotificationCategoryRegistry.register()
    }

    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        let userInfo = notification.request.content.userInfo

        // A push about a widget, with the app open: refetch that widget so
        // its card reflects what the push just said (a parent accepted, a
        // round closed) instead of what it loaded at launch.
        if case .homeWidget(let widgetId)? = NotificationTapRouter.destination(for: userInfo) {
            NotificationCenter.default.post(name: .refreshHomeWidget, object: widgetId)
        }

        // The proximity banner is for a closed app; in the foreground the
        // home chip covers it. Swallow it here (the request is consumed and
        // the next replan reschedules the place).
        if let type = userInfo["type"] as? String,
           type == ProximityNotificationScheduler.notificationType,
           UIApplication.shared.applicationState == .active {
            completionHandler([])
            return
        }

        // Special handling for connection_accepted notifications
        if let type = userInfo["type"] as? String, type == "connection_accepted" {
            // Show a custom in-app alert for connection accepted
            if let acceptedByUserId = userInfo["acceptedByUserId"] as? String {
                UserDefaults.standard.set(acceptedByUserId, forKey: "newlyAcceptedConnectionId")
                UserDefaults.standard.set(Date(), forKey: "newlyAcceptedConnectionDate")
                
                // Show custom alert
                DispatchQueue.main.async {
                    if let topViewController = self.getTopViewController() {
                        let alertController = UIAlertController(
                            title: "Connection Accepted! 🎉",
                            message: notification.request.content.body,
                            preferredStyle: .alert
                        )
                        
                        alertController.addAction(UIAlertAction(title: "View Network", style: .default) { _ in
                            NotificationCenter.default.post(name: Notification.Name("NavigateToNetwork"), object: nil)
                        })
                        
                        alertController.addAction(UIAlertAction(title: "Later", style: .cancel))
                        
                        topViewController.present(alertController, animated: true)
                    }
                }
                
                // Don't show the system notification since we're showing custom alert
                completionHandler([.badge, .sound])
                return
            }
        }
        
        // For other notifications, show normally with list option for persistence
        completionHandler([.alert, .badge, .sound, .list])
    }
    
    private func getTopViewController() -> UIViewController? {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           var topController = window.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            return topController
        }
        return nil
    }
    
    // Removed storeDailySummaryData - notification doesn't contain full data
    // The DailySummaryViewController will fetch data from API when presented
    
    // Removed cleanupOldSummaries - no longer storing summaries locally
    
    private func presentDailySummary(with userInfo: [AnyHashable: Any]) {
        Logger.debug("📊 Presenting daily summary modal (will fetch fresh data)")
        
        // Function to actually present the modal
        let presentModal = {
            guard let topViewController = self.getTopViewController() else {
                Logger.debug("⚠️ Could not find top view controller")
                // Try again after a short delay in case app is still launching
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.presentDailySummary(with: userInfo)
                }
                return
            }
            
            // Create and present daily summary view controller
            // It will fetch its own data from the API
            let summaryVC = DailySummaryViewController()
            
            // Check if topViewController can present
            if topViewController.presentedViewController != nil {
                topViewController.dismiss(animated: false) {
                    topViewController.present(summaryVC, animated: true) {
                        Logger.debug("✅ Daily summary modal presented")
                    }
                }
            } else {
                topViewController.present(summaryVC, animated: true) {
                    Logger.debug("✅ Daily summary modal presented")
                }
            }
        }
        
        // Present immediately if on main thread, otherwise dispatch to main
        if Thread.isMainThread {
            presentModal()
        } else {
            DispatchQueue.main.async {
                presentModal()
            }
        }
    }
    
    private func showDailySummaryAlert(data: [String: Any], from viewController: UIViewController) {
        Logger.debug("📊 Showing daily summary alert with data: \(data)")
        
        // Parse the notification data
        let newPlaces = Int(data["newPlaces"] as? String ?? "0") ?? 0
        let newConnections = Int(data["newConnections"] as? String ?? "0") ?? 0
        let unreadMessages = Int(data["unreadMessages"] as? String ?? "0") ?? 0
        let placeComments = Int(data["placeComments"] as? String ?? "0") ?? 0
        let placeLikes = Int(data["placeLikes"] as? String ?? "0") ?? 0
        
        // Build the message
        var messageComponents: [String] = []
        
        if newPlaces > 0 {
            messageComponents.append("📍 \(newPlaces) new place\(newPlaces > 1 ? "s" : "") from your network")
        }
        
        if newConnections > 0 {
            messageComponents.append("👥 \(newConnections) new connection\(newConnections > 1 ? "s" : "")")
        }
        
        if unreadMessages > 0 {
            messageComponents.append("💬 \(unreadMessages) unread message\(unreadMessages > 1 ? "s" : "")")
        }
        
        if placeComments > 0 || placeLikes > 0 {
            var activities: [String] = []
            if placeComments > 0 {
                activities.append("\(placeComments) comment\(placeComments > 1 ? "s" : "")")
            }
            if placeLikes > 0 {
                activities.append("\(placeLikes) like\(placeLikes > 1 ? "s" : "")")
            }
            messageComponents.append("❤️ \(activities.joined(separator: " and ")) on your places")
        }
        
        // Parse and add top contributors if available
        if let contributorsString = data["topContributors"] as? String,
           let contributorsData = contributorsString.data(using: .utf8),
           let contributors = try? JSONSerialization.jsonObject(with: contributorsData) as? [[String: Any]],
           !contributors.isEmpty {
            let topContributor = contributors.first
            if let name = topContributor?["name"] as? String,
               let count = topContributor?["count"] as? Int {
                messageComponents.append("\n🌟 Top contributor: \(name) (\(count) place\(count > 1 ? "s" : ""))")
            }
        }
        
        let message = messageComponents.isEmpty ? "No new activity today" : messageComponents.joined(separator: "\n\n")
        
        // Format date for subtitle
        let today = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        let dateString = dateFormatter.string(from: today)
        
        // Create alert
        let alert = UIAlertController(
            title: "Your Weekly Summary",
            message: "\(dateString)\n\n\(message)",
            preferredStyle: .alert
        )
        
        // Add actions based on what's available
        if newPlaces > 0 {
            alert.addAction(UIAlertAction(title: "View New Places", style: .default) { _ in
                if let tabBar = UIApplication.shared.windows.first?.rootViewController as? UITabBarController {
                    tabBar.selectedIndex = 0
                }
            })
        }
        
        if unreadMessages > 0 {
            alert.addAction(UIAlertAction(title: "View Messages", style: .default) { _ in
                NotificationCenter.default.post(name: Notification.Name("NavigateToMessages"), object: nil)
            })
        }
        
        if newConnections > 0 {
            alert.addAction(UIAlertAction(title: "View Network", style: .default) { _ in
                NotificationCenter.default.post(name: Notification.Name("NavigateToNetwork"), object: nil)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        
        viewController.present(alert, animated: true) {
            Logger.debug("✅ Daily summary alert presented")
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        notificationActions.handle(response, completion: completionHandler)
    }

    /// The buttons on notifications, and a plain tap → `handleNotificationTap`.
    private lazy var notificationActions = NotificationActionHandler(
        onTap: { [weak self] userInfo in self?.handleNotificationTap(userInfo: userInfo) },
        topViewController: { [weak self] in self?.getTopViewController() }
    )


    private func postOrStashDeepLink(navName: String, pending: String, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        DispatchQueue.main.async {
            let mainUIReady = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .contains { $0.rootViewController is CirclesTabBarController }

            if mainUIReady {
                NotificationCenter.default.post(name: Notification.Name(navName), object: object, userInfo: userInfo)
            } else {
                UserDefaults.standard.set(pending, forKey: "pendingDeepLink")
            }
        }
    }

    private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        guard let type = NotificationTapRouter.type(in: userInfo) else {
            Logger.debug("⚠️ No notification type found")
            return
        }
        Logger.debug("🔔 AppDelegate: Handling notification tap for type: \(type)")
        guard let destination = NotificationTapRouter.destination(for: userInfo) else {
            Logger.debug("⚠️ AppDelegate: nowhere to go for notification type: \(type)")
            return
        }
        perform(destination)
    }

    /// The side effects for a routed tap. Everything that needs UIKit,
    /// UserDefaults or the scene lives here; the choice of destination is the
    /// router's, and tested.
    private func perform(_ destination: NotificationDestination) {
        let center = NotificationCenter.default
        switch destination {
        case .conversation(let id):
            center.post(name: Notification.Name("NavigateToConversation"), object: id)
        case .messages:
            center.post(name: Notification.Name("NavigateToMessages"), object: nil)
        case .homeWidget(let id):
            center.post(name: .navigateToHomeWidget, object: id)
        case .postcardOrder(let id):
            postOrStashDeepLink(navName: Notification.Name.navigateToHomeWidget.rawValue, pending: "postcard-order:\(id)",
                                object: "postcard", userInfo: ["orderId": id])
        case .dailyQuote(let id):
            postOrStashDeepLink(navName: Notification.Name.navigateToHomeWidget.rawValue, pending: "quote:\(id)",
                                object: "quotes", userInfo: ["quoteId": id])
        case .suggestions(let placeId, let suggestionId):
            var info: [String: Any] = [:]
            if let placeId { info["placeId"] = placeId }
            if let suggestionId { info["suggestionId"] = suggestionId }
            center.post(name: Notification.Name("NavigateToSuggestions"), object: nil, userInfo: info.isEmpty ? nil : info)
        case .circle(let id, let showComments):
            center.post(name: Notification.Name("NavigateToCircle"), object: id, userInfo: showComments.map { ["showComments": $0] })
        case .place(let id, let showComments):
            center.post(name: Notification.Name("NavigateToPlace"), object: id, userInfo: showComments.map { ["showComments": $0] })
        case .activity(let id):
            center.post(name: Notification.Name("NavigateToActivity"), object: id)
        case .network(let showPending):
            center.post(name: Notification.Name("NavigateToNetwork"), object: nil, userInfo: showPending ? ["showPending": true] : nil)
        case .connectionAccepted(let userId):
            UserDefaults.standard.set(userId, forKey: "newlyAcceptedConnectionId")
            UserDefaults.standard.set(Date(), forKey: "newlyAcceptedConnectionDate")
            center.post(name: Notification.Name("NavigateToNetwork"), object: userId)
        case .dailySummary:
            // Informational only: clear the badge, then open the summary (or
            // stash it for the scene on a cold start).
            UIApplication.shared.applicationIconBadgeNumber = 0
            postOrStashDeepLink(navName: "NavigateToDailySummary", pending: "daily-summary", userInfo: ["showDailySummary": true])
        case .postOrStash(let navName, let pending, let object):
            postOrStashDeepLink(navName: navName, pending: pending, object: object)
        case .proximityCheckIn(let placeId):
            ProximityNotificationScheduler.markPromptedToday(placeId: placeId)
            postOrStashDeepLink(navName: Notification.Name.navigateToCheckIn.rawValue, pending: "check-in:\(placeId)", object: placeId)
        case .piggyBank:
            center.post(name: Notification.Name("NavigateToPiggyBank"), object: nil)
        case .userProfile(let id):
            sceneDelegate?.navigateToUserProfile(userId: id)
        case .video(let id):
            sceneDelegate?.navigateToVideo(videoId: id)
        case .meTab:
            sceneDelegate?.navigateToMeTab()
        case .deepLink(let url):
            sceneDelegate?.handleDeepLink(url)
        }
    }



    /// The connected scene's delegate — owner of all deep-link navigation.
    private var sceneDelegate: SceneDelegate? {
        UIApplication.shared.connectedScenes
            .compactMap { $0.delegate as? SceneDelegate }
            .first
    }
    

    // MARK: - MessagingDelegate
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Logger.debug("🔔 Firebase FCM registration token received: \(fcmToken ?? "nil")")
        
        if let fcmToken = fcmToken {
            Logger.debug("🔔 FCM Token length: \(fcmToken.count) characters")
            
            // Save FCM token to UserDefaults
            UserDefaults.standard.set(fcmToken, forKey: "FCMToken")
            UserDefaults.standard.synchronize()
            Logger.debug("🔔 Saved FCM token to UserDefaults")
            
            // Send FCM token to backend
            Logger.debug("🔔 Calling NotificationService.registerDeviceToken")
            NotificationService.shared.registerDeviceToken(fcmToken)
            
            // Also check if user is logged in and update backend
            if AuthService.shared.isLoggedIn {
                Logger.debug("🔔 User is logged in, updating push token")
                NotificationService.shared.updatePushToken()
            } else {
                Logger.debug("🔔 User not logged in, token will be sent on next login")
            }
        } else {
            Logger.debug("🔔 ❌ Received nil FCM token")
        }
    }
}

