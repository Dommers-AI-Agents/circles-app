import UIKit
import FBSDKCoreKit

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
        APIService.shared.configure(environment: .production)
        #else
        APIService.shared.configure(environment: .production)
        #endif
        
        // Check if there's a deep link to handle
        if let url = connectionOptions.urlContexts.first?.url {
            handleDeepLink(url)
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
            
            // Try to restore Google Sign-In session if user previously signed in with Google
            if AuthService.shared.getAuthProvider() == "google" {
                print("🎬 User previously signed in with Google, attempting to restore session")
                SocialAuthService.shared.restoreGoogleSignInSession { result in
                    switch result {
                    case .success:
                        print("🎬 Google session restored successfully")
                    case .failure(let error):
                        print("🎬 Google session restoration failed: \(error)")
                        // The backend token might still be valid even if Google session expired
                    }
                }
            }
        }
        
        // Add authentication state listener
        AuthService.shared.addAuthStateListener(id: authListenerId) { [weak self] isLoggedIn in
            print("🎬 SceneDelegate auth state listener called with isLoggedIn: \(isLoggedIn)")
            self?.updateRootViewController(isLoggedIn: isLoggedIn)
        }
        
        window?.makeKeyAndVisible()
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Handle deep links when the app is already running
        if let url = URLContexts.first?.url {
            // First check if it's a Facebook callback
            if ApplicationDelegate.shared.application(UIApplication.shared, open: url, sourceApplication: nil, annotation: nil) {
                return
            }
            
            // Handle other deep links
            handleDeepLink(url)
        }
    }
    
    private func updateRootViewController(isLoggedIn: Bool) {
        if isLoggedIn {
            // First, fetch the current user to ensure profile data is available
            AuthService.shared.fetchCurrentUser { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    switch result {
                    case .success:
                        // User data loaded successfully, show main interface
                        let mainTabController = CirclesTabBarController()
                        
                        // Animate transition if there's an existing view controller
                        if self.window?.rootViewController != nil {
                            UIView.transition(with: self.window!, duration: 0.3, options: .transitionCrossDissolve, animations: {
                                self.window?.rootViewController = mainTabController
                            }, completion: nil)
                        } else {
                            self.window?.rootViewController = mainTabController
                        }
                        
                    case .failure:
                        // Failed to load user data, clear session and show login
                        print("Failed to load user data on session restore, clearing session")
                        AuthService.shared.logout()
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
    
    private func handleDeepLink(_ url: URL) {
        // Parse the URL and navigate to the appropriate screen
        guard url.scheme == "circles" else { return }
        
        // Handle different path components
        let components = url.pathComponents
        
        // Handle deep linking after app is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if components.count >= 2 {
                if components[1] == "circle" && components.count >= 3 {
                    // Example: circles://circle/circle_123
                    let circleId = components[2]
                    self.navigateToCircle(circleId: circleId)
                } else if components[1] == "place" && components.count >= 3 {
                    // Example: circles://place/place_123
                    let placeId = components[2]
                    self.navigateToPlace(placeId: placeId)
                } else if components[1] == "user" && components.count >= 3 {
                    // Example: circles://user/user_123
                    let userId = components[2]
                    self.navigateToUserProfile(userId: userId)
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
            AuthService.shared.refreshToken { _ in }
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Save any necessary data
    }
}