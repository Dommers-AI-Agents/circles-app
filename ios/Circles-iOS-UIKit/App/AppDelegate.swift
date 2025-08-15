//
//  AppDelegate.swift
//  Circles-iOS-UIKit
//
//  Created by Wesley Sgroi on 5/17/25.
//

import UIKit
import AuthenticationServices
import GoogleSignIn
import FacebookCore
import GooglePlaces
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
        print("🚀 DAILY SUMMARY VERSION: App launched with enhanced notification handling - v2025.8.1-fixed")
        // Override point for customization after application launch.
        
        // Suppress Google Maps SDK duplicate class warnings in debug builds
        #if DEBUG
        UserDefaults.standard.set(false, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
        #endif
        
        // Configure Firebase first
        FirebaseApp.configure()
        
        // Configure Firebase Messaging
        Messaging.messaging().delegate = self
        
        // Get FCM token if available
        print("🔔 ===== PUSH NOTIFICATION SETUP =====")
        print("🔔 App launched at: \(Date())")
        print("🔔 Requesting FCM token on app launch...")
        
        Messaging.messaging().token { token, error in
            if let error = error {
                print("🔔 ❌ Error fetching FCM registration token: \(error)")
                print("🔔 Error domain: \(error._domain)")
                print("🔔 Error code: \(error._code)")
            } else if let token = token {
                print("🔔 ✅ FCM registration token retrieved on launch")
                print("🔔 Token length: \(token.count) characters")
                print("🔔 Token preview: \(token.prefix(20))...")
                
                // Save to UserDefaults
                UserDefaults.standard.set(token, forKey: "FCMToken")
                UserDefaults.standard.synchronize()
                print("🔔 Token saved to UserDefaults")
                
                // Send to backend if user is logged in
                if AuthService.shared.isLoggedIn {
                    print("🔔 User is logged in on launch, registering token with backend")
                    print("🔔 Backend URL: \(APIEnvironment.current.baseURL)")
                    NotificationService.shared.registerDeviceToken(token)
                } else {
                    print("🔔 User not logged in on launch, token saved for later registration")
                }
            } else {
                print("🔔 ⚠️ No FCM token available on launch")
            }
        }
        
        // Note: AuthManager removed - using AuthService directly
        
        // Initialize media cache and cleanup expired content
        DispatchQueue.global(qos: .background).async {
            print("🧹 Starting media cache cleanup...")
            MediaCacheService.shared.cleanupExpiredCache()
            
            let stats = MediaCacheService.shared.getCacheStatistics()
            print("📊 Media Cache Statistics:")
            print("   - Total items: \(stats.itemCount)")
            print("   - Total size: \(stats.totalSize / 1024 / 1024)MB")
            print("   - User content: \(stats.userContentSize / 1024 / 1024)MB")
            print("   - Network content: \(stats.networkContentSize / 1024 / 1024)MB")
        }
        
        // Configure NetworkManager after Firebase is initialized
        NetworkManager.shared.configure()
        
        // Clear any pending API requests from previous session
        APIService.shared.clearPendingRequests()
        
        // Start SSE service for real-time updates
        SSEService.shared.connect()
        
        // Initialize Visit Detection Service
        VisitDetectionService.shared.configure()
        print("📍 Visit Detection Service initialized")
        
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
            print("❌ Failed to load Google configuration from GoogleService-Info.plist")
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
            print("⚠️ WARNING: Required Google Sign-In URL scheme not found")
        }
        
        // Try to restore previous Google Sign-In session
        // Note: The SDK automatically manages session persistence in newer versions
        
        // Initialize Facebook SDK
        print("📘 Initializing Facebook SDK")
        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        
        // Initialize Google Places SDK using API_KEY from GoogleService-Info.plist
        if let gmsApiKey = plist["API_KEY"] as? String {
            GMSPlacesClient.provideAPIKey(gmsApiKey)
            print("📍 Google Places SDK initialized (photos only)")
        } else {
            print("❌ Failed to load Google Places API key")
        }
        
        // Initialize Subscription Service
        print("💎 Initializing Subscription Service")
        Task {
            await SubscriptionManager.shared.initialize()
        }
        
        // Start observing for promoted purchases
        print("💎 Starting StoreKit Observer for promoted purchases")
        StoreKitObserver.shared.startObserving()
        
        // Configure Push Notifications
        print("🔔 Configuring Push Notifications")
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
        print("📱 URL received in AppDelegate: \(url)")

        // Check if the URL is for Apple Sign-In
        if url.absoluteString.contains("appleid") {
            print("🍎 Handling Apple Sign-In callback URL")
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
        print("📘 Facebook SDK handling result: \(facebookHandled)")
        
        if facebookHandled {
            print("📘 Facebook SDK successfully handled URL")
            return true
        }
        
        // Handle LinkedIn OAuth callback
        // URL format: com.favcircles.circles://linkedin/callback?code=xxx&state=yyy
        if url.scheme == "com.favcircles.circles" {
            print("🔗 Checking if LinkedIn callback - URL: \(url.absoluteString)")
            print("🔗 URL host: \(url.host ?? "nil"), path: \(url.path)")
            
            // Check if this is a LinkedIn callback
            if url.absoluteString.contains("linkedin") {
                print("🔗 LinkedIn OAuth callback received")
                let handled = SocialAuthService.shared.handleLinkedInCallback(url: url)
                return handled
            }
        }
        
        // Handle other URL schemes your app may use
        print("📱 URL not recognized by auth providers, checking app's deep linking")
        
        // Forward deep links to the active scene
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let sceneDelegate = windowScene.delegate as? SceneDelegate {
            print("📱 Forwarding URL to SceneDelegate for deep link handling")
            sceneDelegate.handleURLContext(url)
        }
        
        return true
    }
    
    // MARK: - Continue Apple Sign-In
    
    @objc func didChangeAuthState(_ notification: Notification) {
        print("🍎 Apple ID credential state changed")
        // Handle sign-out when Apple ID is revoked
        AuthService.shared.logout { _ in
            // This will trigger the auth state listener in SceneDelegate
        }
    }
    
    // MARK: - Background Tasks
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📍 Background fetch triggered")
        
        // Sync any pending visits
        VisitDetectionService.shared.syncPendingVisits()
        
        // Complete with new data status
        completionHandler(.newData)
    }
    
    // MARK: - Push Notification Methods
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("🔔 ===== APNS REGISTRATION SUCCESS =====")
        print("🔔 APNs Device Token: \(token)")
        print("🔔 Token length: \(token.count) characters")
        
        // Set APNs token for Firebase Messaging
        print("🔔 Setting APNs token for Firebase Messaging...")
        Messaging.messaging().apnsToken = deviceToken
        print("🔔 APNs token set, waiting for FCM token...")
        
        // The FCM token will be received in the MessagingDelegate callback
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("🔔 Failed to register for remote notifications: \(error)")
    }
    
    // MARK: - Background Notification Handling
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("🔔 Received remote notification in background/terminated state")
        print("🔔 UserInfo: \(userInfo)")
        
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
        // Connection request actions
        let acceptAction = UNNotificationAction(
            identifier: "ACCEPT_CONNECTION",
            title: "Accept",
            options: [.authenticationRequired, .foreground]
        )
        let declineAction = UNNotificationAction(
            identifier: "DECLINE_CONNECTION",
            title: "Decline",
            options: [.authenticationRequired, .destructive]
        )
        let connectionCategory = UNNotificationCategory(
            identifier: "CONNECTION_REQUEST",
            actions: [acceptAction, declineAction],
            intentIdentifiers: [],
            options: [.customDismissAction, .hiddenPreviewsShowTitle]
        )
        
        // Message actions
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_MESSAGE",
            title: "Reply",
            options: [.authenticationRequired],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type your message..."
        )
        let viewAction = UNNotificationAction(
            identifier: "VIEW_MESSAGE",
            title: "View",
            options: [.authenticationRequired, .foreground]
        )
        let messageCategory = UNNotificationCategory(
            identifier: "NEW_MESSAGE",
            actions: [replyAction, viewAction],
            intentIdentifiers: [],
            options: [.customDismissAction, .hiddenPreviewsShowTitle]
        )
        
        // Place suggestion actions
        let viewPlaceAction = UNNotificationAction(
            identifier: "VIEW_PLACE",
            title: "View Place",
            options: [.authenticationRequired, .foreground]
        )
        let saveAction = UNNotificationAction(
            identifier: "SAVE_PLACE",
            title: "Save to Circle",
            options: [.authenticationRequired]
        )
        let suggestionCategory = UNNotificationCategory(
            identifier: "PLACE_SUGGESTION",
            actions: [viewPlaceAction, saveAction],
            intentIdentifiers: [],
            options: [.customDismissAction, .hiddenPreviewsShowTitle]
        )
        
        // Activity update category
        let viewActivityAction = UNNotificationAction(
            identifier: "VIEW_ACTIVITY",
            title: "View",
            options: [.authenticationRequired, .foreground]
        )
        let activityCategory = UNNotificationCategory(
            identifier: "ACTIVITY_UPDATE",
            actions: [viewActivityAction],
            intentIdentifiers: [],
            options: [.customDismissAction, .hiddenPreviewsShowTitle]
        )
        
        // Set categories
        UNUserNotificationCenter.current().setNotificationCategories([
            connectionCategory,
            messageCategory,
            suggestionCategory,
            activityCategory
        ])
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        let userInfo = notification.request.content.userInfo
        
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
    
    private func presentDailySummary(with userInfo: [AnyHashable: Any]) {
        print("📊 Presenting daily summary modal")
        print("📊 UserInfo keys: \(userInfo.keys)")
        print("📊 Raw userInfo: \(userInfo)")
        
        // Function to actually present the modal
        let presentModal = {
            guard let topViewController = self.getTopViewController() else {
                print("⚠️ Could not find top view controller")
                // Try again after a short delay in case app is still launching
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.presentDailySummary(with: userInfo)
                }
                return
            }
            
            // Convert userInfo to String dictionary and extract all possible data locations
            var notificationData: [String: Any] = [:]
            
            // First, add all root level string keys
            for (key, value) in userInfo {
                if let stringKey = key as? String {
                    notificationData[stringKey] = value
                }
            }
            
            // Check if data is nested in "gcm.notification.data" (common FCM pattern)
            if let gcmData = userInfo["gcm.notification.data"] as? String,
               let data = gcmData.data(using: .utf8),
               let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("📊 Found data in gcm.notification.data")
                // Merge the nested data
                for (key, value) in jsonData {
                    notificationData[key] = value
                }
            }
            
            // Check if data is in a "data" field
            if let dataField = userInfo["data"] as? [String: Any] {
                print("📊 Found data in 'data' field")
                // Merge the nested data
                for (key, value) in dataField {
                    notificationData[key] = value
                }
            }
            
            // Check for individual fields at root level (FCM sometimes flattens custom data)
            let dailySummaryFields = ["newPlaces", "newConnections", "unreadMessages", 
                                     "placeComments", "placeLikes", "placeCategories", 
                                     "topContributors", "summaryDate", "type"]
            
            for field in dailySummaryFields {
                // Check with "gcm.notification." prefix (another FCM pattern)
                if let value = userInfo["gcm.notification.\(field)"] as? String {
                    print("📊 Found \(field) at gcm.notification.\(field): \(value)")
                    notificationData[field] = value
                }
            }
            
            print("📊 AppDelegate: Presenting daily summary with processed data:")
            print("📊 Keys: \(notificationData.keys.sorted())")
            print("📊 Full processed data: \(notificationData)")
            
            // Create and present daily summary
            let summaryVC = DailySummaryViewController(notificationData: notificationData)
            
            // Check if topViewController can present
            if topViewController.presentedViewController != nil {
                topViewController.dismiss(animated: false) {
                    topViewController.present(summaryVC, animated: true) {
                        print("✅ Daily summary modal presented")
                    }
                }
            } else {
                topViewController.present(summaryVC, animated: true) {
                    print("✅ Daily summary modal presented")
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
        print("📊 Showing daily summary alert with data: \(data)")
        
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
            title: "Your Daily Summary",
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
            print("✅ Daily summary alert presented")
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification response (tap or action)
        let userInfo = response.notification.request.content.userInfo
        
        // Handle notification actions
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself
            handleNotificationTap(userInfo: userInfo)
            
        case "ACCEPT_CONNECTION":
            // Handle connection accept action
            if let requestId = userInfo["requestId"] as? String {
                handleAcceptConnection(requestId: requestId)
            }
            
        case "DECLINE_CONNECTION":
            // Handle connection decline action
            if let requestId = userInfo["requestId"] as? String {
                handleDeclineConnection(requestId: requestId)
            }
            
        case "REPLY_MESSAGE":
            // Handle message reply action
            if let textResponse = response as? UNTextInputNotificationResponse,
               let conversationId = userInfo["conversationId"] as? String {
                handleQuickReply(conversationId: conversationId, message: textResponse.userText)
            }
            
        case "VIEW_MESSAGE":
            // Navigate to specific conversation
            if let conversationId = userInfo["conversationId"] as? String {
                NotificationCenter.default.post(
                    name: Notification.Name("NavigateToConversation"),
                    object: conversationId
                )
            }
            
        case "VIEW_PLACE":
            // Navigate to place detail
            if let placeId = userInfo["placeId"] as? String {
                NotificationCenter.default.post(
                    name: Notification.Name("NavigateToPlace"),
                    object: placeId
                )
            }
            
        case "SAVE_PLACE":
            // Handle save place action
            if let placeId = userInfo["placeId"] as? String {
                handleSavePlace(placeId: placeId)
            }
            
        case "VIEW_ACTIVITY":
            // Navigate based on activity type
            handleViewActivity(userInfo: userInfo)
            
        default:
            break
        }
        
        completionHandler()
    }
    
    // MARK: - Notification Action Handlers
    
    private func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        // Check for notification type
        var notificationType: String?
        
        // Check multiple possible locations for the type field
        if let type = userInfo["type"] as? String {
            notificationType = type
        } else if let customData = userInfo["customData"] as? [String: Any],
                  let type = customData["type"] as? String {
            notificationType = type
        } else if let data = userInfo["data"] as? [String: Any],
                  let type = data["type"] as? String {
            notificationType = type
        }
        
        guard let type = notificationType else {
            print("⚠️ No notification type found")
            return
        }
        
        // Handle different notification types when user taps the notification
        switch type {
        case "new_message":
            NotificationCenter.default.post(name: Notification.Name("NavigateToMessages"), object: nil)
        case "new_suggestion":
            NotificationCenter.default.post(name: Notification.Name("NavigateToSuggestions"), object: nil)
        case "new_place":
            if let circleId = userInfo["circleId"] as? String {
                NotificationCenter.default.post(name: Notification.Name("NavigateToCircle"), object: circleId)
            }
        case "connection_request":
            NotificationCenter.default.post(name: Notification.Name("NavigateToNetwork"), object: nil)
        case "connection_accepted":
            if let acceptedByUserId = userInfo["acceptedByUserId"] as? String {
                UserDefaults.standard.set(acceptedByUserId, forKey: "newlyAcceptedConnectionId")
                UserDefaults.standard.set(Date(), forKey: "newlyAcceptedConnectionDate")
            }
            NotificationCenter.default.post(name: Notification.Name("NavigateToNetwork"), object: nil)
        case "daily_summary":
            // Clear badge count since daily summaries are informational only
            UIApplication.shared.applicationIconBadgeNumber = 0
            
            // Present daily summary modal
            DispatchQueue.main.async {
                self.presentDailySummary(with: userInfo)
            }
        default:
            break
        }
    }
    
    private func handleAcceptConnection(requestId: String) {
        // Show loading indicator
        DispatchQueue.main.async {
            if let topVC = self.getTopViewController() {
                let loading = AlertPresenter.showLoading(message: "Accepting connection...", from: topVC)
                
                // Make API call to accept connection
                NetworkManager.shared.acceptConnectionRequest(requestId: requestId) { result in
                    loading.dismiss(animated: true) {
                        switch result {
                        case .success:
                            // Show success and navigate to network
                            AlertPresenter.showSuccess("Connection accepted!", from: topVC)
                            NotificationCenter.default.post(name: Notification.Name("NavigateToNetwork"), object: nil)
                        case .failure(let error):
                            AlertPresenter.showError(error, from: topVC)
                        }
                    }
                }
            }
        }
    }
    
    private func handleDeclineConnection(requestId: String) {
        // Make API call to decline connection
        NetworkManager.shared.declineConnectionRequest(requestId: requestId) { result in
            DispatchQueue.main.async {
                if let topVC = self.getTopViewController() {
                    switch result {
                    case .success:
                        // Just show a brief confirmation
                        AlertPresenter.showBriefMessage("Connection declined", from: topVC)
                    case .failure(let error):
                        AlertPresenter.showError(error, from: topVC)
                    }
                }
            }
        }
    }
    
    private func handleQuickReply(conversationId: String, message: String) {
        // Send the message via messaging service
        MessagingService.shared.sendQuickReply(conversationId: conversationId, message: message) { result in
            DispatchQueue.main.async {
                if let topVC = self.getTopViewController() {
                    switch result {
                    case .success:
                        // Show brief success
                        AlertPresenter.showBriefMessage("Reply sent", from: topVC)
                    case .failure(let error):
                        // Show error and offer to open conversation
                        AlertPresenter.showConfirmation(
                            title: "Reply Failed",
                            message: "Failed to send reply. Open conversation?",
                            from: topVC
                        ) {
                            NotificationCenter.default.post(
                                name: Notification.Name("NavigateToConversation"),
                                object: conversationId
                            )
                        }
                    }
                }
            }
        }
    }
    
    private func handleSavePlace(placeId: String) {
        // Show circle picker to save place
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("SavePlaceToCircle"),
                object: placeId
            )
        }
    }
    
    private func handleViewActivity(userInfo: [AnyHashable: Any]) {
        // Navigate based on activity type
        if let activityType = userInfo["activityType"] as? String {
            switch activityType {
            case "new_place", "place_liked":
                if let circleId = userInfo["circleId"] as? String {
                    NotificationCenter.default.post(
                        name: Notification.Name("NavigateToCircle"),
                        object: circleId
                    )
                }
            case "new_connection":
                NotificationCenter.default.post(name: Notification.Name("NavigateToNetwork"), object: nil)
            case "comment":
                if let placeId = userInfo["placeId"] as? String {
                    NotificationCenter.default.post(
                        name: Notification.Name("NavigateToPlace"),
                        object: placeId
                    )
                }
            default:
                // Navigate to home/activity feed
                NotificationCenter.default.post(name: Notification.Name("NavigateToHome"), object: nil)
            }
        }
    }
    
    // MARK: - MessagingDelegate
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("🔔 Firebase FCM registration token received: \(fcmToken ?? "nil")")
        
        if let fcmToken = fcmToken {
            print("🔔 FCM Token length: \(fcmToken.count) characters")
            
            // Save FCM token to UserDefaults
            UserDefaults.standard.set(fcmToken, forKey: "FCMToken")
            UserDefaults.standard.synchronize()
            print("🔔 Saved FCM token to UserDefaults")
            
            // Send FCM token to backend
            print("🔔 Calling NotificationService.registerDeviceToken")
            NotificationService.shared.registerDeviceToken(fcmToken)
            
            // Also check if user is logged in and update backend
            if AuthService.shared.isLoggedIn {
                print("🔔 User is logged in, updating push token")
                NotificationService.shared.updatePushToken()
            } else {
                print("🔔 User not logged in, token will be sent on next login")
            }
        } else {
            print("🔔 ❌ Received nil FCM token")
        }
    }
}

