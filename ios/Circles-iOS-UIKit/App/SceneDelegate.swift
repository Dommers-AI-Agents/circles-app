import UIKit
import FacebookCore
import FirebaseMessaging

// MARK: - Response Types
struct ShareValidationResponse: Codable {
    let success: Bool
    let isValid: Bool
    let accessLevel: String?
    let message: String?
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var authListenerId = "SceneDelegate"

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // Create a window with the window scene
        window = UIWindow(windowScene: windowScene)
        
        // Configure API environment
        #if DEBUG
        // Use production environment even in DEBUG to connect to Firebase backend
        APIService.shared.configure(environment: .production, loggingEnabled: false)
        #else
        APIService.shared.configure(environment: .production, loggingEnabled: false)
        #endif
        
        // Check if there's a deep link to handle
        if let url = connectionOptions.urlContexts.first?.url {
            Logger.debug("SceneDelegate: URL received on launch: \(url.absoluteString)")
            
            // Check if it's a LinkedIn callback
            if url.scheme == "com.favcircles.circles" && url.absoluteString.contains("linkedin") {
                Logger.debug("LinkedIn callback detected on app launch")
                // Delay handling to ensure SocialAuthService is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    _ = SocialAuthService.shared.handleLinkedInCallback(url: url)
                }
            } else {
                handleDeepLink(url)
            }
        }
        
        // Show main interface immediately if user is logged in (faster loading)
        if AuthService.shared.isLoggedIn {
            // Check if we have cached data - if so, show main interface immediately
            if PreloadManager.shared.getPreloadedData() != nil {
                Logger.debug("Cached data available, showing main interface immediately")
                let mainTabController = CirclesTabBarController()
                window?.rootViewController = mainTabController
            } else {
                // No cached data, show splash screen
                let splashVC = SplashScreenViewController()
                window?.rootViewController = splashVC
            }
            
            // Perform token refresh on app launch if user is logged in
            Logger.debug("User is logged in, checking token validity")
            
            // Check if token is expired first
            if AuthService.shared.isTokenExpired() {
                Logger.info("Token is expired, logging out immediately")
                AuthService.shared.logout()
            } else if AuthService.shared.shouldRefreshToken() {
                // Token is not expired but should be refreshed soon
                Logger.info("Token needs refresh, refreshing...")
                AuthService.shared.refreshToken { result in
                    switch result {
                    case .success:
                        Logger.info("Token refreshed successfully on app launch")
                    case .failure(let error):
                        Logger.error("Token refresh failed: \(error)")
                        // Don't force logout here - let 401 handling take care of it
                    }
                }
            } else {
                Logger.debug("Token is still valid")
            }
            
            // Restore Google Sign-In session asynchronously (don't block UI)
            if AuthService.shared.getAuthProvider() == "google" && !AuthService.shared.isTokenExpired() {
                DispatchQueue.global(qos: .background).async {
                    Logger.debug("User previously signed in with Google, restoring session in background")
                    SocialAuthService.shared.restoreGoogleSignInSession { result in
                        switch result {
                        case .success:
                            Logger.debug("Google session restored successfully")
                        case .failure(let error):
                            Logger.warning("Google session restoration failed: \(error)")
                        }
                    }
                }
            }
        }
        
        // Add authentication state listener
        AuthService.shared.addAuthStateListener(id: authListenerId) { [weak self] isLoggedIn in
            Logger.debug("SceneDelegate auth state listener called with isLoggedIn: \(isLoggedIn)")
            self?.updateRootViewController(isLoggedIn: isLoggedIn)
        }
        
        // Setup promoted purchase notifications
        setupPromotedPurchaseNotifications()
        
        window?.makeKeyAndVisible()
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        print("📱 SceneDelegate: openURLContexts called with \(URLContexts.count) contexts")
        
        // Handle deep links when the app is already running
        if let url = URLContexts.first?.url {
            print("📱 SceneDelegate: Processing URL: \(url.absoluteString)")
            print("📱 SceneDelegate: URL scheme: \(url.scheme ?? "nil")")
            print("📱 SceneDelegate: URL host: \(url.host ?? "nil")")
            print("📱 SceneDelegate: URL path: \(url.path)")
            print("📱 SceneDelegate: URL pathComponents: \(url.pathComponents)")
            
            // First check if it's a Facebook callback
            if ApplicationDelegate.shared.application(UIApplication.shared, open: url, sourceApplication: nil, annotation: nil) {
                print("📘 Handled by Facebook SDK")
                return
            }
            
            // Check if it's a LinkedIn callback
            if url.scheme == "com.favcircles.circles" && url.absoluteString.contains("linkedin") {
                print("🔗 LinkedIn callback detected in SceneDelegate")
                let handled = SocialAuthService.shared.handleLinkedInCallback(url: url)
                if handled {
                    print("🔗 LinkedIn callback handled successfully")
                    return
                }
            }
            
            // Handle other deep links
            print("📱 SceneDelegate: Calling handleDeepLink with URL: \(url.absoluteString)")
            handleDeepLink(url)
        }
    }
    
    // Handle Universal Links
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        print("📱 SceneDelegate: continue userActivity called")
        
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            print("📱 SceneDelegate: Not a web browsing activity")
            return
        }
        
        print("📱 SceneDelegate: Universal Link received: \(url.absoluteString)")
        print("📱 SceneDelegate: URL host: \(url.host ?? "nil")")
        print("📱 SceneDelegate: URL path: \(url.path)")
        
        // Handle Universal Links from our backend
        if url.host == "circles-backend-196924649787.us-central1.run.app" {
            handleUniversalLink(url)
        }
    }
    
    private func updateRootViewController(isLoggedIn: Bool) {
        if isLoggedIn {
            // Show splash screen with preloading
            let splashVC = SplashScreenViewController()
            
            // Animate transition if there's an existing view controller
            if window?.rootViewController != nil {
                UIView.transition(with: window!, duration: 0.3, options: .transitionCrossDissolve, animations: {
                    self.window?.rootViewController = splashVC
                }, completion: nil)
            } else {
                window?.rootViewController = splashVC
            }
            
            // Add failsafe timeout for splash screen - reduced to 10 seconds
            var hasCompleted = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self, weak splashVC] in
                guard let self = self, let splashVC = splashVC else { return }
                guard !hasCompleted else { return } // Already completed normally
                
                print("⏰ SceneDelegate: Splash screen timeout reached (10 seconds)")
                
                // Show error with retry option
                let alert = UIAlertController(
                    title: "Loading Timeout",
                    message: "The app is taking longer than expected to load. This might be due to network issues.",
                    preferredStyle: .alert
                )
                
                alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
                    print("🔄 User chose to retry from splash screen timeout")
                    self.updateRootViewController(isLoggedIn: true)
                })
                
                alert.addAction(UIAlertAction(title: "Logout", style: .destructive) { _ in
                    print("🚪 User chose to logout from splash screen timeout")
                    AuthService.shared.logout()
                })
                
                splashVC.present(alert, animated: true)
            }
            
            // Start preloading all data
            PreloadManager.shared.preloadAllData(
                progressHandler: { progress, status in
                    print("🚦 Progress update: \(progress) - \(status)")
                    splashVC.updateProgress(progress, status: status)
                },
                completion: { [weak self] result in
                    hasCompleted = true // Mark as completed to prevent timeout handler
                    print("🚦 PreloadManager completion called")
                    switch result {
                    case .success(let preloadedData):
                        // Data loaded successfully, show main interface
                        print("🚦 Success - showing main interface")
                        DispatchQueue.main.async {
                            guard let self = self else { 
                                print("❌ Self is nil in completion")
                                return 
                            }
                            
                            let mainTabController = CirclesTabBarController()
                            
                            // Pass preloaded data to the circles home view controller
                            if let navController = mainTabController.viewControllers?[0] as? UINavigationController,
                               let circlesVC = navController.topViewController as? CirclesHomeViewController {
                                circlesVC.setPreloadedData(preloadedData)
                            }
                            
                            // Complete splash animation and transition
                            splashVC.completeLoading {
                                UIView.transition(with: self.window!, duration: 0.5, options: .transitionCrossDissolve, animations: {
                                    self.window?.rootViewController = mainTabController
                                }, completion: { _ in
                                    // Check for pending deep links after login
                                    self.handlePendingDeepLink()
                                    // Process any pending connection invites
                                    NetworkManager.shared.processPendingConnectionInvite()
                                    
                                    // Check if user is new and should see onboarding
                                    if OnboardingManager.shared.shouldShowContactsOnboarding() {
                                        self.showContactsOnboarding()
                                    } else if self.shouldShowNotificationOnboarding() {
                                        // Show notification onboarding for users who haven't seen it
                                        self.showNotificationOnboarding()
                                    } else {
                                        // Check if user needs tutorial
                                        OnboardingManager.shared.checkIfUserNeedsTutorial { needsTutorial in
                                            if needsTutorial {
                                                OnboardingManager.shared.startTutorial()
                                                Logger.info("New user detected - starting onboarding tutorial")
                                            }
                                        }
                                    }
                                })
                            }
                        }
                        
                    case .failure(let error):
                        // Failed to load data, show error and logout
                        print("Failed to preload data: \(error)")
                        
                        // If it's a user not found error, logout immediately
                        if error is AuthError && (error as! AuthError) == .userNotFound {
                            AuthService.shared.logout()
                        } else {
                            // For other errors, show an alert with more details
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self else { return }
                                
                                // Provide more specific error messages
                                var message = "Unable to load your data. Please try again."
                                var showRetry = true
                                
                                if let nsError = error as? NSError {
                                    if nsError.domain == "PreloadManager" {
                                        switch nsError.code {
                                        case -1:
                                            message = "Loading is taking longer than expected. This may be due to a slow network connection."
                                        case -2:
                                            message = "You are not logged in. Please log in again."
                                            showRetry = false
                                        case -3:
                                            message = "Your session has expired. Please log in again."
                                            showRetry = false
                                        default:
                                            message = nsError.localizedDescription
                                        }
                                    } else if nsError.domain == NSURLErrorDomain {
                                        message = "Network connection error. Please check your internet connection and try again."
                                    }
                                }
                                
                                let alert = UIAlertController(
                                    title: "Loading Error",
                                    message: message,
                                    preferredStyle: .alert
                                )
                                
                                if showRetry {
                                    alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
                                        self.updateRootViewController(isLoggedIn: true)
                                    })
                                }
                                
                                alert.addAction(UIAlertAction(title: "Logout", style: .destructive) { _ in
                                    AuthService.shared.logout()
                                })
                                
                                splashVC.present(alert, animated: true)
                            }
                        }
                    }
                }
            )
        } else {
            // User is not logged in, show authentication flow
            let loginVC = LoginViewController()
            let navController = UINavigationController(rootViewController: loginVC)
            
            // Animate transition if there's an existing view controller
            if window?.rootViewController != nil {
                UIView.transition(with: window!, duration: 0.3, options: .transitionCrossDissolve, animations: {
                    self.window?.rootViewController = navController
                }, completion: nil)
            } else {
                window?.rootViewController = navController
            }
        }
    }
    
    // Public method to handle URLs from AppDelegate
    func handleURLContext(_ url: URL) {
        print("📱 SceneDelegate: handleURLContext called with URL: \(url.absoluteString)")
        handleDeepLink(url)
    }
    
    private func handleUniversalLink(_ url: URL) {
        // Handle Universal Links from our backend
        print("📱 SceneDelegate: Processing Universal Link with path: \(url.path)")
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        // Check if it's an /app/* path
        if pathComponents.first == "app" && pathComponents.count >= 2 {
            let appPath = pathComponents[1]
            
            switch appPath {
            case "daily-summary":
                navigateToDailySummary()
            case "open":
                // Handle generic open with path parameter
                if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let pathParam = urlComponents.queryItems?.first(where: { $0.name == "path" })?.value {
                    handleOpenPath(pathParam)
                }
            case "video":
                if pathComponents.count >= 3 {
                    let videoId = pathComponents[2]
                    navigateToVideo(videoId: videoId)
                }
            case "circle":
                if pathComponents.count >= 3 {
                    let circleId = pathComponents[2]
                    navigateToCircle(circleId: circleId)
                }
            case "connect":
                if pathComponents.count >= 3 {
                    let userId = pathComponents[2]
                    handleConnectionInvite(from: userId)
                }
            default:
                print("📱 SceneDelegate: Unknown app path: \(appPath)")
            }
        } else if pathComponents.first == "daily-summary" {
            navigateToDailySummary()
        } else if pathComponents.first == "video" && pathComponents.count >= 2 {
            let videoId = pathComponents[1]
            navigateToVideo(videoId: videoId)
        } else if pathComponents.first == "circle" && pathComponents.count >= 2 {
            let circleId = pathComponents[1]
            navigateToCircle(circleId: circleId)
        } else if pathComponents.first == "connect" && pathComponents.count >= 2 {
            let userId = pathComponents[1]
            handleConnectionInvite(from: userId)
        }
    }
    
    private func handleOpenPath(_ path: String) {
        // Handle specific paths
        if path == "settings/notifications" {
            navigateToNotificationSettings()
        } else if path == "network/find-friends" {
            // Navigate to find friends
            guard let tabBarController = window?.rootViewController as? CirclesTabBarController else { return }
            tabBarController.selectedIndex = 1 // Network tab
        } else if path == "add-place" {
            // Navigate to add place
            guard let tabBarController = window?.rootViewController as? CirclesTabBarController else { return }
            tabBarController.selectedIndex = 0 // Home tab
            // Trigger add place action
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        // Parse the URL and navigate to the appropriate screen
        guard url.scheme == "circles" else {
            print("📱 SceneDelegate: URL scheme '\(url.scheme ?? "nil")' is not 'circles', returning")
            return
        }
        
        print("📱 SceneDelegate: Processing deep link with path: \(url.path)")
        print("📱 SceneDelegate: Path components: \(url.pathComponents)")
        print("📱 SceneDelegate: Path components count: \(url.pathComponents.count)")
        
        // Handle different path components
        let components = url.pathComponents
        
        // Log each component for debugging
        for (index, component) in components.enumerated() {
            print("📱 SceneDelegate: Component[\(index)]: '\(component)'")
        }
        
        // Handle deep linking after app is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("📱 SceneDelegate: Inside dispatch queue, processing components")
            
            // First check if this is a host-based URL format (e.g., circles://connect/userId)
            if url.host == "connect" {
                // Handle circles://connect/userId format where "connect" is the host
                print("📱 SceneDelegate: Detected 'connect' as host")
                let userId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                print("📱 SceneDelegate: Extracted userId from path: \(userId)")
                if !userId.isEmpty {
                    print("📱 SceneDelegate: Calling handleConnectionInvite with userId: \(userId)")
                    self.handleConnectionInvite(from: userId)
                    return
                }
            }
            
            // Handle video deep links (e.g., circles://video/[videoId])
            if url.host == "video" {
                print("📱 SceneDelegate: Detected 'video' as host")
                let videoId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                print("📱 SceneDelegate: Extracted videoId from path: \(videoId)")
                if !videoId.isEmpty {
                    print("📱 SceneDelegate: Calling handleVideoDeepLink with videoId: \(videoId)")
                    self.handleVideoDeepLink(videoId: videoId)
                    return
                }
            }
            
            // Handle referral deep links (e.g., circles://referral?code=ABC123)
            if url.host == "referral" {
                print("📱 SceneDelegate: Detected 'referral' as host")
                if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value {
                    print("📱 SceneDelegate: Found referral code: \(code)")
                    self.handleReferralCode(code)
                    return
                }
            }
            
            // Handle daily summary deep link (e.g., circles://daily-summary)
            if url.host == "daily-summary" {
                print("📱 SceneDelegate: Detected 'daily-summary' deep link")
                self.navigateToDailySummary()
                return
            }
            
            // Handle settings/notifications deep link (e.g., circles://settings/notifications)
            if url.host == "settings" && url.path == "/notifications" {
                print("📱 SceneDelegate: Detected 'settings/notifications' deep link")
                self.navigateToNotificationSettings()
                return
            }
            
            // Handle circle deep links with share tokens (e.g., circles://circle/circleId?share=shareToken)
            if url.host == "circle" {
                print("📱 SceneDelegate: Detected 'circle' as host")
                let circleId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                print("📱 SceneDelegate: Extracted circleId from path: \(circleId)")
                
                // Check for share token in query parameters
                if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let shareToken = urlComponents.queryItems?.first(where: { $0.name == "share" })?.value {
                    print("📱 SceneDelegate: Found share token: \(shareToken)")
                    self.handleSharedCircleWithToken(circleId: circleId, shareToken: shareToken)
                    return
                } else if !circleId.isEmpty {
                    // Regular circle navigation without share token
                    self.navigateToCircle(circleId: circleId)
                    return
                }
            }
            
            // Then check path-based URL format (e.g., circles:///connect/userId)
            if components.count >= 2 {
                if components[1] == "circle" && components.count >= 3 {
                    // Example: circles://circle/circle_123
                    let circleId = components[2]
                    
                    // Check for share token in query parameters
                    if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       let shareToken = urlComponents.queryItems?.first(where: { $0.name == "share" })?.value {
                        print("📱 SceneDelegate: Found share token in path format: \(shareToken)")
                        self.handleSharedCircleWithToken(circleId: circleId, shareToken: shareToken)
                    } else {
                        self.navigateToCircle(circleId: circleId)
                    }
                } else if components[1] == "share" && components.count >= 4 && components[2] == "circle" {
                    // Example: circles://share/circle/shareId_123
                    let shareId = components[3]
                    self.handleSharedCircle(shareId: shareId)
                } else if components[1] == "place" && components.count >= 3 {
                    // Example: circles://place/place_123
                    let placeId = components[2]
                    self.navigateToPlace(placeId: placeId)
                } else if components[1] == "user" && components.count >= 3 {
                    // Example: circles://user/user_123
                    let userId = components[2]
                    self.navigateToUserProfile(userId: userId)
                } else if components[1] == "connect" && components.count >= 3 {
                    // Example: circles:///connect/user_123 (with triple slash)
                    let userId = components[2]
                    print("📱 SceneDelegate: Handling connection invite from user: \(userId)")
                    self.handleConnectionInvite(from: userId)
                }
            }
        }
    }
    
    private func navigateToCircle(circleId: String, isSharedViaLink: Bool = false) {
        guard AuthService.shared.isLoggedIn,
              let tabBarController = window?.rootViewController as? CirclesTabBarController else {
            // Store the deep link target to navigate after login
            UserDefaults.standard.set("circle:\(circleId)", forKey: "pendingDeepLink")
            return
        }
        
        // Switch to the Circles tab
        tabBarController.selectedIndex = 0
        
        // Find circle data and navigate
        CircleService.shared.fetchCircleById(id: circleId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let circle):
                    if let navController = tabBarController.selectedViewController as? UINavigationController {
                        let detailVC = CircleDetailViewController(circle: circle, isSharedViaLink: isSharedViaLink)
                        navController.pushViewController(detailVC, animated: true)
                    }
                case .failure:
                    // Show error alert
                    break
                }
            }
        }
    }
    
    private func navigateToPlace(placeId: String) {
        guard AuthService.shared.isLoggedIn,
              let tabBarController = window?.rootViewController as? CirclesTabBarController else {
            // Store the deep link target to navigate after login
            UserDefaults.standard.set("place:\(placeId)", forKey: "pendingDeepLink")
            return
        }
        
        // Find place data and navigate
        PlaceService.shared.fetchPlaceById(id: placeId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let place):
                    if let navController = tabBarController.selectedViewController as? UINavigationController {
                        let detailVC = PlaceDetailViewController(place: place)
                        navController.pushViewController(detailVC, animated: true)
                    }
                case .failure:
                    // Show error alert
                    break
                }
            }
        }
    }
    
    private func navigateToUserProfile(userId: String) {
        guard AuthService.shared.isLoggedIn,
              let tabBarController = window?.rootViewController as? CirclesTabBarController else {
            // Store the deep link target to navigate after login
            UserDefaults.standard.set("user:\(userId)", forKey: "pendingDeepLink")
            return
        }
        
        // Switch to the Profile tab
        tabBarController.selectedIndex = 3
        
        // If it's not the current user, we need to navigate to their profile
        if userId != AuthService.shared.getUserId() {
            UserService.shared.fetchUserProfile(userId: userId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let user):
                        if let navController = tabBarController.selectedViewController as? UINavigationController {
                            let profileVC = ProfileViewController(user: user)
                            navController.pushViewController(profileVC, animated: true)
                        }
                    case .failure:
                        // Show error alert
                        break
                    }
                }
            }
        }
    }
    
    private func handleSharedCircleWithToken(circleId: String, shareToken: String) {
        // First, validate the share token with the backend
        // This doesn't require authentication
        APIService.shared.request(
            endpoint: "circles/share/validate",
            method: .post,
            body: ["circleId": circleId, "shareToken": shareToken],
            requiresAuth: false
        ) { [weak self] (result: Result<ShareValidationResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if response.isValid {
                        // Try to fetch the circle details to check if it's public
                        CircleService.shared.fetchCircleByIdPublic(id: circleId) { circleResult in
                            DispatchQueue.main.async {
                                switch circleResult {
                                case .success(let circle):
                                    // Circle is public, allow viewing even without login
                                    if let tabBarController = self?.window?.rootViewController as? CirclesTabBarController,
                                       let navController = tabBarController.selectedViewController as? UINavigationController {
                                        let detailVC = CircleDetailViewController(circle: circle, isSharedViaLink: true)
                                        navController.pushViewController(detailVC, animated: true)
                                    }
                                case .failure:
                                    // Circle is not public or error occurred, require login
                                    if AuthService.shared.isLoggedIn {
                                        // User is logged in, navigate normally
                                        self?.navigateToCircle(circleId: circleId, isSharedViaLink: true)
                                    } else {
                                        // User not logged in, store deep link and prompt login
                                        UserDefaults.standard.set("shareToken:\(circleId):\(shareToken)", forKey: "pendingDeepLink")
                                        
                                        let alert = UIAlertController(
                                            title: "Login Required",
                                            message: "Please login to view this circle",
                                            preferredStyle: .alert
                                        )
                                        alert.addAction(UIAlertAction(title: "Login", style: .default) { _ in
                                            // The auth state listener will handle showing login screen
                                        })
                                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                                        
                                        if let rootVC = self?.window?.rootViewController {
                                            rootVC.present(alert, animated: true)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        // Share is invalid or expired
                        self?.showShareError(message: response.message ?? "This share link is no longer valid")
                    }
                    
                case .failure(let error):
                    self?.showShareError(message: "Failed to validate share link: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func showShareAccessBanner(accessLevel: String) {
        guard let tabBarController = window?.rootViewController as? CirclesTabBarController,
              let currentVC = tabBarController.selectedViewController else { return }
        
        let banner = UIView()
        banner.backgroundColor = .systemBlue
        banner.layer.cornerRadius = 10
        banner.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = accessLevel == "viewOnly" ? "View-only access" : "Limited access"
        label.textColor = .white
        label.font = .systemFont(ofSize: 14)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        banner.addSubview(label)
        currentVC.view.addSubview(banner)
        
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: currentVC.view.safeAreaLayoutGuide.topAnchor, constant: 20),
            banner.centerXAnchor.constraint(equalTo: currentVC.view.centerXAnchor),
            banner.heightAnchor.constraint(equalToConstant: 40),
            banner.widthAnchor.constraint(equalToConstant: 150),
            
            label.centerXAnchor.constraint(equalTo: banner.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
        ])
        
        // Animate and remove after 5 seconds
        banner.alpha = 0
        UIView.animate(withDuration: 0.3) {
            banner.alpha = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            UIView.animate(withDuration: 0.3, animations: {
                banner.alpha = 0
            }) { _ in
                banner.removeFromSuperview()
            }
        }
    }
    
    private func showShareError(message: String) {
        let alert = UIAlertController(
            title: "Unable to Access Circle",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let rootVC = window?.rootViewController {
            rootVC.present(alert, animated: true)
        }
    }
    
    private func handleSharedCircle(shareId: String) {
        // If user is not logged in, store the share ID and prompt login
        guard AuthService.shared.isLoggedIn else {
            UserDefaults.standard.set("share:\(shareId)", forKey: "pendingDeepLink")
            
            // Show alert prompting user to login
            let alert = UIAlertController(
                title: "Login Required",
                message: "Please login to view the shared circle",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Login", style: .default) { _ in
                // The auth state listener will handle showing login screen
            })
            
            if let rootVC = window?.rootViewController {
                rootVC.present(alert, animated: true)
            }
            return
        }
        
        // Accept the shared circle
        NetworkManager.shared.acceptSharedCircle(shareId: shareId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let sharedCircle):
                    // Navigate to the shared circle
                    self?.navigateToCircle(circleId: sharedCircle.circleId)
                    
                    // Show success message
                    if let tabBarController = self?.window?.rootViewController as? CirclesTabBarController,
                       let currentVC = tabBarController.selectedViewController {
                        let banner = UIView()
                        banner.backgroundColor = .systemGreen
                        banner.layer.cornerRadius = 10
                        banner.translatesAutoresizingMaskIntoConstraints = false
                        
                        let label = UILabel()
                        label.text = "Circle imported successfully!"
                        label.textColor = .white
                        label.translatesAutoresizingMaskIntoConstraints = false
                        
                        banner.addSubview(label)
                        currentVC.view.addSubview(banner)
                        
                        NSLayoutConstraint.activate([
                            banner.topAnchor.constraint(equalTo: currentVC.view.safeAreaLayoutGuide.topAnchor, constant: 20),
                            banner.centerXAnchor.constraint(equalTo: currentVC.view.centerXAnchor),
                            banner.heightAnchor.constraint(equalToConstant: 50),
                            banner.widthAnchor.constraint(equalToConstant: 250),
                            
                            label.centerXAnchor.constraint(equalTo: banner.centerXAnchor),
                            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
                        ])
                        
                        // Animate and remove after 3 seconds
                        UIView.animate(withDuration: 0.3) {
                            banner.alpha = 1.0
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            UIView.animate(withDuration: 0.3, animations: {
                                banner.alpha = 0
                            }) { _ in
                                banner.removeFromSuperview()
                            }
                        }
                    }
                    
                case .failure(let error):
                    // Show error alert
                    let alert = UIAlertController(
                        title: "Import Failed",
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    
                    if let rootVC = self?.window?.rootViewController {
                        rootVC.present(alert, animated: true)
                    }
                }
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // Release any resources associated with this scene
        AuthService.shared.removeAuthStateListener(id: authListenerId)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Check for any pending notifications or updates
        if AuthService.shared.isLoggedIn {
            // Clear notification badge when user opens the app
            print("🔔 SceneDelegate: Clearing notification badge on app activation")
            NotificationService.shared.clearBadge()
            
            // Proactively check and refresh token if needed
            if AuthService.shared.isTokenExpired() {
                print("🔄 SceneDelegate: Token expired, refreshing proactively on scene activation")
                AuthService.shared.refreshToken { result in
                    switch result {
                    case .success():
                        print("✅ SceneDelegate: Token refreshed successfully on activation")
                    case .failure(let error):
                        print("❌ SceneDelegate: Failed to refresh token on activation: \(error)")
                        // Don't force logout here, let the user continue and handle errors when they occur
                    }
                }
            }
            
            // Ensure push token is registered
            if let fcmToken = UserDefaults.standard.string(forKey: "FCMToken") {
                print("🎬 ===== SCENE ACTIVE - TOKEN CHECK =====")
                print("🎬 Scene became active at: \(Date())")
                print("🎬 Found saved FCM token: \(fcmToken.prefix(20))...")
                print("🎬 Re-registering token with backend to ensure it's current")
                NotificationService.shared.registerDeviceToken(fcmToken)
            } else {
                print("🎬 ===== SCENE ACTIVE - NO TOKEN =====")
                print("🎬 Scene became active, but no FCM token saved")
                print("🎬 Requesting new FCM token...")
                Messaging.messaging().token { token, error in
                    if let token = token {
                        print("🎬 Got new FCM token: \(token.prefix(20))...")
                        NotificationService.shared.registerDeviceToken(token)
                    } else if let error = error {
                        print("🎬 Failed to get FCM token: \(error)")
                    }
                }
            }
        }
        
        // Check for app updates
        checkForAppUpdates()
    }
    
    private func handleConnectionInvite(from userId: String) {
        print("📱 SceneDelegate: handleConnectionInvite called with userId: \(userId)")
        print("📱 SceneDelegate: Current user logged in: \(AuthService.shared.isLoggedIn)")
        print("📱 SceneDelegate: Current user ID: \(AuthService.shared.getUserId() ?? "nil")")
        
        // If user is not logged in, store the connection invite and prompt login
        guard AuthService.shared.isLoggedIn else {
            print("📱 SceneDelegate: User not logged in, storing pending connection invite")
            // Store both as pending deep link and specific connection invite
            UserDefaults.standard.set("connect:\(userId)", forKey: "pendingDeepLink")
            NetworkManager.storePendingConnectionInvite(userId: userId)
            
            // Show alert prompting user to login
            let alert = UIAlertController(
                title: "Connection Invite",
                message: "Please login to connect with this user",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Login", style: .default) { _ in
                // The auth state listener will handle showing login screen
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            if let rootVC = window?.rootViewController {
                rootVC.present(alert, animated: true)
            }
            return
        }
        
        // Handle the connection invite
        print("📱 SceneDelegate: About to call NetworkManager.handleConnectionInvite")
        NetworkManager.shared.handleConnectionInvite(from: userId) { [weak self] result in
            print("📱 SceneDelegate: NetworkManager.handleConnectionInvite callback received")
            DispatchQueue.main.async {
                switch result {
                case .success(let connection):
                    print("📱 SceneDelegate: Connection successful! Connection ID: \(connection.id), Status: \(connection.status)")
                    // Refresh connections list to ensure UI is updated
                    NetworkManager.shared.loadConnections()
                    
                    // Navigate to the network tab
                    if let tabBarController = self?.window?.rootViewController as? CirclesTabBarController {
                        tabBarController.selectedIndex = 2 // Network tab
                        
                        // Show success message
                        let banner = UIView()
                        banner.backgroundColor = .systemGreen
                        banner.layer.cornerRadius = 10
                        banner.translatesAutoresizingMaskIntoConstraints = false
                        
                        let label = UILabel()
                        let labelText = connection.status == .accepted ? "Connected successfully!" : "Connection request sent!"
                        label.text = labelText
                        label.textColor = .white
                        label.translatesAutoresizingMaskIntoConstraints = false
                        
                        banner.addSubview(label)
                        tabBarController.view.addSubview(banner)
                        
                        NSLayoutConstraint.activate([
                            banner.topAnchor.constraint(equalTo: tabBarController.view.safeAreaLayoutGuide.topAnchor, constant: 20),
                            banner.centerXAnchor.constraint(equalTo: tabBarController.view.centerXAnchor),
                            banner.heightAnchor.constraint(equalToConstant: 50),
                            banner.widthAnchor.constraint(equalToConstant: 250),
                            
                            label.centerXAnchor.constraint(equalTo: banner.centerXAnchor),
                            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
                        ])
                        
                        // Animate and remove after 3 seconds
                        UIView.animate(withDuration: 0.3) {
                            banner.alpha = 1.0
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            UIView.animate(withDuration: 0.3, animations: {
                                banner.alpha = 0
                            }) { _ in
                                banner.removeFromSuperview()
                            }
                        }
                    }
                    
                case .failure(let error):
                    print("📱 SceneDelegate: Connection failed with error: \(error)")
                    // Show error alert
                    let errorMessage: String
                    if error.localizedDescription.contains("Already connected") {
                        errorMessage = "You are already connected to this user"
                    } else {
                        errorMessage = "Failed to send connection request"
                    }
                    
                    let alert = UIAlertController(
                        title: "Connection Failed",
                        message: errorMessage,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    
                    if let rootVC = self?.window?.rootViewController {
                        rootVC.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    private func handlePendingDeepLink() {
        guard let pendingLink = UserDefaults.standard.string(forKey: "pendingDeepLink") else { return }
        
        // Clear the pending link
        UserDefaults.standard.removeObject(forKey: "pendingDeepLink")
        
        // Parse and handle the link
        let components = pendingLink.split(separator: ":")
        if components.count >= 2 {
            let type = String(components[0])
            
            // Add a delay to ensure the UI is fully loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                switch type {
                case "shareToken":
                    // Format: shareToken:circleId:shareToken
                    if components.count >= 3 {
                        let circleId = String(components[1])
                        let shareToken = String(components[2])
                        self.handleSharedCircleWithToken(circleId: circleId, shareToken: shareToken)
                    }
                case "circle":
                    let id = String(components[1])
                    self.navigateToCircle(circleId: id)
                case "place":
                    let id = String(components[1])
                    self.navigateToPlace(placeId: id)
                case "user":
                    let id = String(components[1])
                    self.navigateToUserProfile(userId: id)
                case "share":
                    let id = String(components[1])
                    self.handleSharedCircle(shareId: id)
                case "connect":
                    let id = String(components[1])
                    self.handleConnectionInvite(from: id)
                case "video":
                    let id = String(components[1])
                    self.navigateToVideo(videoId: id)
                case "daily-summary":
                    self.navigateToDailySummary()
                case "settings":
                    if components.count >= 2 && components[1] == "notifications" {
                        self.navigateToNotificationSettings()
                    }
                default:
                    break
                }
            }
        }
    }
    
    private func checkForAppUpdates() {
        UpdateService.shared.checkForUpdates { [weak self] isUpdateAvailable, releaseNotes, isRequired in
            guard isUpdateAvailable else { return }
            
            // Find the topmost view controller
            if let window = self?.window,
               let rootViewController = window.rootViewController {
                
                var topController = rootViewController
                
                // Navigate through navigation controllers
                if let navController = topController as? UINavigationController {
                    topController = navController.visibleViewController ?? navController
                }
                
                // Navigate through tab bar controllers
                if let tabController = topController as? UITabBarController {
                    if let selectedNav = tabController.selectedViewController as? UINavigationController {
                        topController = selectedNav.visibleViewController ?? selectedNav
                    } else if let selected = tabController.selectedViewController {
                        topController = selected
                    }
                }
                
                // Navigate through presented view controllers
                while let presented = topController.presentedViewController {
                    topController = presented
                }
                
                // Show update prompt
                if isRequired {
                    // For required updates, show alert immediately
                    UpdateService.shared.showUpdatePrompt(
                        in: topController,
                        releaseNotes: releaseNotes,
                        isRequired: true
                    )
                } else {
                    // For optional updates, show banner
                    UpdateService.shared.showUpdateBanner(
                        in: topController,
                        isRequired: false
                    )
                }
            }
        }
    }
    
    private func showContactsOnboarding() {
        guard let tabBarController = window?.rootViewController as? CirclesTabBarController else { return }
        
        // Mark that we're showing contacts permission
        OnboardingManager.shared.markContactsPermissionShown()
        
        // Create contacts permission view controller
        let contactsPermissionVC = ContactsPermissionViewController()
        
        // Configure callbacks
        contactsPermissionVC.configure(
            onPermissionGranted: { [weak self] in
                // User completed contacts flow
                Logger.info("User completed contacts onboarding flow")
                
                // Check if we should show tutorial
                OnboardingManager.shared.checkIfUserNeedsTutorial { needsTutorial in
                    if needsTutorial {
                        OnboardingManager.shared.startTutorial()
                        Logger.info("Starting tutorial after contacts onboarding")
                    }
                }
            },
            onSkip: { [weak self] in
                // User skipped contacts permission
                Logger.info("User skipped contacts onboarding")
                
                // Check if we should show tutorial
                OnboardingManager.shared.checkIfUserNeedsTutorial { needsTutorial in
                    if needsTutorial {
                        OnboardingManager.shared.startTutorial()
                        Logger.info("Starting tutorial after skipping contacts")
                    }
                }
            }
        )
        
        // Present in navigation controller
        let navController = UINavigationController(rootViewController: contactsPermissionVC)
        navController.modalPresentationStyle = .fullScreen
        
        // Present from the tab bar controller
        tabBarController.present(navController, animated: true)
    }
    
    private func shouldShowNotificationOnboarding() -> Bool {
        // Check if we've already shown notification onboarding
        let hasShownOnboarding = UserDefaults.standard.bool(forKey: "hasShownNotificationOnboarding")
        if hasShownOnboarding {
            return false
        }
        
        // Check if notifications are already enabled
        let semaphore = DispatchSemaphore(value: 0)
        var isEnabled = false
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            isEnabled = settings.authorizationStatus == .authorized
            semaphore.signal()
        }
        
        semaphore.wait()
        
        // Only show if notifications are not enabled
        return !isEnabled
    }
    
    private func showNotificationOnboarding() {
        guard let tabBarController = window?.rootViewController as? CirclesTabBarController else { return }
        
        Logger.info("Showing notification onboarding")
        
        // Create notification onboarding view controller
        let notificationVC = NotificationOnboardingViewController()
        
        // Configure completion callback
        notificationVC.onCompletion = { [weak self] in
            // Check if user needs tutorial after notification onboarding
            OnboardingManager.shared.checkIfUserNeedsTutorial { needsTutorial in
                if needsTutorial {
                    OnboardingManager.shared.startTutorial()
                    Logger.info("Starting tutorial after notification onboarding")
                }
            }
        }
        
        // Present in navigation controller
        let navController = UINavigationController(rootViewController: notificationVC)
        navController.modalPresentationStyle = .fullScreen
        
        // Present from the tab bar controller
        tabBarController.present(navController, animated: true)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // You might want to save any unsaved changes here
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Check authentication status and refresh token if needed
        if AuthService.shared.isLoggedIn {
            // Refresh if token is expired or will expire soon
            if AuthService.shared.shouldRefreshToken() {
                print("🎬 Token needs refresh on foreground, refreshing...")
                AuthService.shared.refreshToken { result in
                    switch result {
                    case .success:
                        print("🎬 Token refreshed successfully on foreground")
                    case .failure(let error):
                        print("🎬 Token refresh failed on foreground: \(error)")
                    }
                }
            }
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Save any necessary data
    }
    
    // MARK: - Referral Code Handling
    
    private func handleReferralCode(_ code: String) {
        print("📱 SceneDelegate: handleReferralCode called with code: \(code)")
        
        // If user is not logged in, save the code for later
        guard AuthService.shared.isLoggedIn else {
            print("📱 SceneDelegate: User not logged in, saving referral code for later")
            ReferralService.shared.savePendingReferralCode(code)
            
            // Show alert prompting user to sign up
            let alert = UIAlertController(
                title: "Referral Code Saved",
                message: "Sign up to get an extra month free with referral code: \(code)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Sign Up", style: .default) { _ in
                // The auth state listener will handle showing auth screen
            })
            alert.addAction(UIAlertAction(title: "Later", style: .cancel))
            
            if let topVC = window?.rootViewController {
                topVC.present(alert, animated: true)
            }
            return
        }
        
        // If user is logged in, check if they've already used a referral code
        if ReferralService.shared.hasUsedReferralCode() {
            print("📱 SceneDelegate: User has already used a referral code")
            
            let alert = UIAlertController(
                title: "Referral Code",
                message: "You have already used a referral code.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            if let topVC = window?.rootViewController {
                topVC.present(alert, animated: true)
            }
            return
        }
        
        // Apply the referral code
        let loading = UIAlertController(title: "Applying Code...", message: nil, preferredStyle: .alert)
        if let topVC = window?.rootViewController {
            topVC.present(loading, animated: true)
        }
        
        ReferralService.shared.applyReferralCode(code) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    switch result {
                    case .success(let response):
                        let alert = UIAlertController(
                            title: "Success!",
                            message: response.message,
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "Great!", style: .default))
                        
                        if let topVC = self?.window?.rootViewController {
                            topVC.present(alert, animated: true)
                        }
                        
                    case .failure(let error):
                        let alert = UIAlertController(
                            title: "Error",
                            message: error.localizedDescription,
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        
                        if let topVC = self?.window?.rootViewController {
                            topVC.present(alert, animated: true)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Video Deep Link Handling
    
    private func handleVideoDeepLink(videoId: String) {
        print("📱 SceneDelegate: handleVideoDeepLink called with videoId: \(videoId)")
        
        // If user is not logged in, store the video link and prompt login
        guard AuthService.shared.isLoggedIn else {
            print("📱 SceneDelegate: User not logged in, storing pending video link")
            UserDefaults.standard.set("video:\(videoId)", forKey: "pendingDeepLink")
            
            // Show alert prompting user to login
            let alert = UIAlertController(
                title: "Login Required",
                message: "Please login to view this video",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Login", style: .default) { _ in
                // The auth state listener will handle showing login screen
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            if let rootVC = window?.rootViewController {
                rootVC.present(alert, animated: true)
            }
            return
        }
        
        // Navigate to video
        navigateToVideo(videoId: videoId)
    }
    
    private func navigateToVideo(videoId: String) {
        guard AuthService.shared.isLoggedIn,
              let tabBarController = window?.rootViewController as? CirclesTabBarController else {
            // Store the deep link target to navigate after login
            UserDefaults.standard.set("video:\(videoId)", forKey: "pendingDeepLink")
            return
        }
        
        // Switch to the Circles tab (home)
        tabBarController.selectedIndex = 0
        
        // Get the navigation controller
        guard let navController = tabBarController.viewControllers?[0] as? UINavigationController,
              let circlesVC = navController.viewControllers.first as? CirclesHomeViewController else {
            return
        }
        
        // Pop to root first
        navController.popToRootViewController(animated: false)
        
        // Load video details and navigate
        APIService.shared.request(
            endpoint: "videos/\(videoId)",
            method: .get
        ) { (result: Result<PlaceVideoResponse, APIError>) in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    // Create a video reels view controller with this single video
                    let videoReelsVC = VideoReelsViewController(reels: [response.data], startIndex: 0)
                    videoReelsVC.placeNavigationHandler = { placeId in
                        // Handle place navigation if needed
                        self.navigateToPlace(placeId: placeId)
                    }
                    navController.pushViewController(videoReelsVC, animated: true)
                    
                case .failure(let error):
                    print("Failed to load video: \(error)")
                    let alert = UIAlertController(
                        title: "Video Not Found",
                        message: "Unable to load the requested video",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    navController.present(alert, animated: true)
                }
            }
        }
    }
    
    // MARK: - Daily Summary Navigation
    
    private func navigateToDailySummary() {
        guard AuthService.shared.isLoggedIn,
              let tabBarController = window?.rootViewController as? CirclesTabBarController else {
            // Store the deep link target to navigate after login
            UserDefaults.standard.set("daily-summary", forKey: "pendingDeepLink")
            return
        }
        
        // Present the DailySummaryViewController modally
        let summaryVC = DailySummaryViewController()
        tabBarController.present(summaryVC, animated: true)
        
        print("📱 SceneDelegate: Presented DailySummaryViewController from daily-summary deep link")
    }
    
    // MARK: - Notification Settings Navigation
    
    private func navigateToNotificationSettings() {
        guard AuthService.shared.isLoggedIn,
              let tabBarController = window?.rootViewController as? CirclesTabBarController else {
            // Store the deep link target to navigate after login
            UserDefaults.standard.set("settings:notifications", forKey: "pendingDeepLink")
            return
        }
        
        // Switch to profile tab (index 3)
        tabBarController.selectedIndex = 3
        
        // Navigate to settings and then to notification preferences
        if let navController = tabBarController.viewControllers?[3] as? UINavigationController {
            // Pop to root first to ensure we're at the profile screen
            navController.popToRootViewController(animated: false)
            
            // Push settings view controller
            let settingsVC = SettingsViewController()
            navController.pushViewController(settingsVC, animated: false)
            
            // Push notification preferences view controller
            let notificationPrefsVC = NotificationPreferencesViewController()
            navController.pushViewController(notificationPrefsVC, animated: true)
        }
    }
    
    // MARK: - Promoted Purchase Handling
    
    private func setupPromotedPurchaseNotifications() {
        // Handle login required for promoted purchase
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowLoginForPromotedPurchase),
            name: Notification.Name("ShowLoginForPromotedPurchase"),
            object: nil
        )
    }
    
    @objc private func handleShowLoginForPromotedPurchase() {
        print("💎 SceneDelegate: Showing login for promoted purchase")
        
        DispatchQueue.main.async { [weak self] in
            // Show login screen
            let loginVC = LoginViewController()
            loginVC.modalPresentationStyle = .fullScreen
            
            // Find the top view controller
            if let window = self?.window,
               var topController = window.rootViewController {
                while let presentedViewController = topController.presentedViewController {
                    topController = presentedViewController
                }
                
                // Present login
                topController.present(loginVC, animated: true) {
                    print("💎 Login screen presented for promoted purchase")
                }
            }
        }
    }
}
