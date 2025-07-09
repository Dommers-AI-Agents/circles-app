import UIKit
import FBSDKCoreKit

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
        
        // Show a loading screen initially if user is logged in
        if AuthService.shared.isLoggedIn {
            let loadingVC = UIViewController()
            loadingVC.view.backgroundColor = Constants.Colors.background
            let activityIndicator = UIActivityIndicatorView(style: .large)
            activityIndicator.color = Constants.Colors.primary
            activityIndicator.translatesAutoresizingMaskIntoConstraints = false
            loadingVC.view.addSubview(activityIndicator)
            NSLayoutConstraint.activate([
                activityIndicator.centerXAnchor.constraint(equalTo: loadingVC.view.centerXAnchor),
                activityIndicator.centerYAnchor.constraint(equalTo: loadingVC.view.centerYAnchor)
            ])
            activityIndicator.startAnimating()
            window?.rootViewController = loadingVC
            
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
            
            // Try to restore Google Sign-In session if user previously signed in with Google
            // BUT only if the token is valid (not expired)
            if AuthService.shared.getAuthProvider() == "google" && !AuthService.shared.isTokenExpired() {
                Logger.debug("User previously signed in with Google and token is valid, attempting to restore session")
                SocialAuthService.shared.restoreGoogleSignInSession { result in
                    switch result {
                    case .success:
                        Logger.debug("Google session restored successfully")
                    case .failure(let error):
                        Logger.warning("Google session restoration failed: \(error)")
                        // The backend token might still be valid even if Google session expired
                    }
                }
            } else if AuthService.shared.getAuthProvider() == "google" && AuthService.shared.isTokenExpired() {
                Logger.debug("User previously signed in with Google but token is expired, skipping Google session restoration")
            }
        }
        
        // Add authentication state listener
        AuthService.shared.addAuthStateListener(id: authListenerId) { [weak self] isLoggedIn in
            Logger.debug("SceneDelegate auth state listener called with isLoggedIn: \(isLoggedIn)")
            self?.updateRootViewController(isLoggedIn: isLoggedIn)
        }
        
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
    
    private func updateRootViewController(isLoggedIn: Bool) {
        if isLoggedIn {
            // First, fetch the current user to ensure profile data is available
            // Add a timeout to prevent indefinite loading
            var didTimeout = false
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                didTimeout = true
                print("⏰ User fetch timed out, forcing logout")
                DispatchQueue.main.async {
                    AuthService.shared.logout()
                }
            }
            
            // Set a 10-second timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeoutWorkItem)
            
            AuthService.shared.fetchCurrentUser { [weak self] result in
                // Cancel the timeout if we got a response
                timeoutWorkItem.cancel()
                
                DispatchQueue.main.async {
                    guard let self = self, !didTimeout else { return }
                    
                    switch result {
                    case .success:
                        // User data loaded successfully, show main interface
                        let mainTabController = CirclesTabBarController()
                        
                        // Animate transition if there's an existing view controller
                        if self.window?.rootViewController != nil {
                            UIView.transition(with: self.window!, duration: 0.3, options: .transitionCrossDissolve, animations: {
                                self.window?.rootViewController = mainTabController
                            }, completion: { _ in
                                // Check for pending deep links after login
                                self.handlePendingDeepLink()
                                // Process any pending connection invites
                                NetworkManager.shared.processPendingConnectionInvite()
                            })
                        } else {
                            self.window?.rootViewController = mainTabController
                            // Check for pending deep links after login
                            self.handlePendingDeepLink()
                            // Process any pending connection invites
                            NetworkManager.shared.processPendingConnectionInvite()
                        }
                        
                    case .failure(let error):
                        // Failed to load user data, clear session and show login
                        print("Failed to load user data on session restore: \(error)")
                        // The AuthService will already clear the session if it's a 404, 
                        // but we'll ensure logout is called for other errors
                        if !(error is AuthError && error as! AuthError == .userNotFound) {
                            AuthService.shared.logout()
                        }
                    }
                }
            }
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
    
    private func navigateToCircle(circleId: String) {
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
                        let detailVC = CircleDetailViewController(circle: circle)
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
        // If user is not logged in, store the share info and prompt login
        guard AuthService.shared.isLoggedIn else {
            UserDefaults.standard.set("shareToken:\(circleId):\(shareToken)", forKey: "pendingDeepLink")
            
            // Show alert prompting user to login
            let alert = UIAlertController(
                title: "Login Required",
                message: "Please login to view the shared circle",
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
        
        // First, validate the share token with the backend
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
                        // If share is valid and user has access, navigate to the circle
                        self?.navigateToCircle(circleId: circleId)
                        
                        // Show access level information if it's a limited share
                        if let accessLevel = response.accessLevel, accessLevel != "full" {
                            self?.showShareAccessBanner(accessLevel: accessLevel)
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
            // Refresh data if needed
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
}
