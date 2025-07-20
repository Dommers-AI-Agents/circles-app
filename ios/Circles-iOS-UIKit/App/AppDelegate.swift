//
//  AppDelegate.swift
//  Circles-iOS-UIKit
//
//  Created by Wesley Sgroi on 5/17/25.
//

import UIKit
import AuthenticationServices
import GoogleSignIn
import FBSDKCoreKit
import GooglePlaces
import Firebase
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // Used to store Apple Sign-In credentials for an extended period
    var appleIDCompletionHandler: ((ASAuthorization?, Error?) -> Void)?
    
    // Keep track of ASAuthorizationController to prevent it from being deallocated
    var authorizationController: ASAuthorizationController?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        // Suppress Google Maps SDK duplicate class warnings in debug builds
        #if DEBUG
        UserDefaults.standard.set(false, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
        #endif
        
        // Configure Firebase first
        FirebaseApp.configure()
        
        // Note: AuthManager removed - using AuthService directly
        
        // Configure NetworkManager after Firebase is initialized
        NetworkManager.shared.configure()
        
        // Clear any pending API requests from previous session
        APIService.shared.clearPendingRequests()
        
        // Start SSE service for real-time updates
        SSEService.shared.connect()
        
        // Set up Apple ID credential state observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didChangeAuthState),
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
        
        // Configure Google Sign-In using configuration from Info.plist
        guard let infoPlist = Bundle.main.infoDictionary,
              let clientId = infoPlist["CLIENT_ID"] as? String,
              let reversedClientId = infoPlist["REVERSED_CLIENT_ID"] as? String else {
            print("❌ Failed to load Google configuration from Info.plist")
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
        
        // Initialize Google Places SDK
        if let gmsApiKey = infoPlist["GMSApiKey"] as? String {
            GMSPlacesClient.provideAPIKey(gmsApiKey)
            print("📍 Google Places SDK initialized (photos only)")
        } else {
            print("❌ Failed to load Google Places API key")
        }
        
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
    
    // MARK: - Push Notification Methods
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("🔔 Device Token: \(token)")
        
        // Save token to UserDefaults for later use
        UserDefaults.standard.set(token, forKey: "PushNotificationToken")
        
        // Send device token to backend
        NotificationService.shared.registerDeviceToken(token)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("🔔 Failed to register for remote notifications: \(error)")
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
            options: []
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
            options: []
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
            options: []
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
            options: []
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
        
        // For other notifications, show normally
        completionHandler([.alert, .badge, .sound])
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
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification response (tap or action)
        let userInfo = response.notification.request.content.userInfo
        print("🔔 Notification response received - Action: \(response.actionIdentifier)")
        print("🔔 UserInfo: \(userInfo)")
        
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
        // Handle different notification types when user taps the notification
        if let type = userInfo["type"] as? String {
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
            default:
                break
            }
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
}

