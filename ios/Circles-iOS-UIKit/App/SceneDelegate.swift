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

            if url.isFileURL {
                // Export file opened with Circles at cold launch — wait for the
                // main interface to be installed before presenting the import flow
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.handleImportFile(url)
                }
            } else
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
        
        // Note: the root view controller is installed by the auth state listener below.
        // addAuthStateListener invokes its listener SYNCHRONOUSLY with the current state
        // (AuthService.addAuthStateListener), so updateRootViewController runs before
        // makeKeyAndVisible() - no blank window, and the cache-first fast path applies.
        if AuthService.shared.isLoggedIn {
            // Perform token refresh on app launch if user is logged in
            Logger.debug("User is logged in, checking token validity")

            // Check if token is expired first
            if AuthService.shared.isTokenExpired() {
                Logger.info("Token is expired, attempting in-place refresh")
                // Refresh in place; only a definitive server rejection logs out
                revalidateExpiredTokenNonDestructively()
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
            if isLoggedIn {
                // Warm the local referral-code cache so connect invites carry it
                ReferralService.shared.prefetchMyReferralCode()
            }
        }
        
        // Setup promoted purchase notifications
        setupPromotedPurchaseNotifications()
        
        window?.makeKeyAndVisible()
        prewarmKeyboard()
    }

    /// The FIRST keyboard presentation in an app's lifetime pays a cold-start
    /// cost (keyboard extension process + input session setup, easily 1–2s on
    /// older devices) — which users feel as "I tapped the search field and
    /// nothing happened." Attaching and immediately resigning a hidden text
    /// field right after the window is up moves that cost to launch, where it
    /// runs concurrently with everything else and nobody is waiting on it.
    private func prewarmKeyboard() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            let field = UITextField(frame: .zero)
            field.autocorrectionType = .no
            window.addSubview(field)
            field.becomeFirstResponder()
            field.resignFirstResponder()
            field.removeFromSuperview()
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        Logger.debug("📱 SceneDelegate: openURLContexts called with \(URLContexts.count) contexts")
        
        // Handle deep links when the app is already running
        if let url = URLContexts.first?.url {
            Logger.debug("📱 SceneDelegate: Processing URL: \(url.absoluteString)")
            Logger.debug("📱 SceneDelegate: URL scheme: \(url.scheme ?? "nil")")
            Logger.debug("📱 SceneDelegate: URL host: \(url.host ?? "nil")")
            Logger.debug("📱 SceneDelegate: URL path: \(url.path)")
            Logger.debug("📱 SceneDelegate: URL pathComponents: \(url.pathComponents)")

            // Export files opened with Circles ("Open in" from Mail/Files) —
            // route into the place import flow
            if url.isFileURL {
                handleImportFile(url)
                return
            }

            // First check if it's a Facebook callback
            if ApplicationDelegate.shared.application(UIApplication.shared, open: url, sourceApplication: nil, annotation: nil) {
                Logger.debug("📘 Handled by Facebook SDK")
                return
            }
            
            // Check if it's a LinkedIn callback
            if url.scheme == "com.favcircles.circles" && url.absoluteString.contains("linkedin") {
                Logger.debug("🔗 LinkedIn callback detected in SceneDelegate")
                let handled = SocialAuthService.shared.handleLinkedInCallback(url: url)
                if handled {
                    Logger.debug("🔗 LinkedIn callback handled successfully")
                    return
                }
            }
            
            // Handle other deep links
            Logger.debug("📱 SceneDelegate: Calling handleDeepLink with URL: \(url.absoluteString)")
            handleDeepLink(url)
        }
    }
    
    // Handle Universal Links
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        Logger.debug("📱 SceneDelegate: continue userActivity called")
        
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            Logger.debug("📱 SceneDelegate: Not a web browsing activity")
            return
        }
        
        Logger.debug("📱 SceneDelegate: Universal Link received: \(url.absoluteString)")
        Logger.debug("📱 SceneDelegate: URL host: \(url.host ?? "nil")")
        Logger.debug("📱 SceneDelegate: URL path: \(url.path)")
        
        // Handle Universal Links from our backend (branded domain and the
        // legacy run.app host - old shared links must keep working)
        let universalLinkHosts = [
            "api.favcircles.com",
            "circles-backend-196924649787.us-central1.run.app"
        ]
        if let host = url.host, universalLinkHosts.contains(host) {
            handleUniversalLink(url)
        }
    }
    
    /// Post-launch side effects that must run once the main interface is installed,
    /// regardless of whether launch went through the splash screen or the cache-first
    /// fast path: pending deep links, connection invites, onboarding, and tutorial.
    private func runPostLaunchSideEffects() {
        handlePendingDeepLink()
        NetworkManager.shared.processPendingConnectionInvite()
        redeemPendingStickerCodeIfNeeded()

        if UserDefaults.standard.bool(forKey: "pendingWelcomeCarousel") {
            // Brand-new signup: welcome carousel first, which chains into the
            // notification prompt. (Contacts onboarding was intentionally cut
            // from first-run — Find Contacts lives in the My Network tab.)
            showWelcomeCarousel()
        } else if shouldShowNotificationOnboarding() {
            showNotificationOnboarding()
        } else {
            OnboardingManager.shared.checkIfUserNeedsTutorial { needsTutorial in
                if needsTutorial {
                    OnboardingManager.shared.startTutorial()
                    Logger.info("New user detected - starting onboarding tutorial")
                }
            }
        }
    }

    /// Handles a place-export file opened with Circles (Mapstr GeoJSON from
    /// Mail, Google Takeout CSV from Files). Copies it out of the inbox and
    /// presents the import flow.
    private func handleImportFile(_ url: URL) {
        guard let tabBarController = window?.rootViewController as? CirclesTabBarController else {
            Logger.debug("📥 Import file received before main interface is ready — ignoring")
            return
        }

        // Files arriving via "Open in" may be security-scoped; copy to tmp
        // before the scope closes
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tempURL)
        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
        } catch {
            Logger.debug("📥 Failed to copy import file: \(error)")
            return
        }

        let source: ImportSource = url.pathExtension.lowercased() == "csv" ? .googleMaps : .mapstr

        var presenter: UIViewController = tabBarController
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        if !SubscriptionManager.shared.isSubscribed {
            SubscriptionManager.shared.showPaywall(from: presenter, reason: .importFeature)
            return
        }

        let importVC = ImportSourceSelectionViewController()
        let navController = UINavigationController(rootViewController: importVC)
        navController.modalPresentationStyle = .fullScreen
        presenter.present(navController, animated: true) {
            importVC.importFiles(at: [tempURL], source: source)
        }
    }

    /// Shows the five-page welcome carousel once right after signup, then
    /// continues the onboarding chain (notifications → tutorial).
    private func showWelcomeCarousel() {
        guard let tabBarController = window?.rootViewController as? CirclesTabBarController else { return }
        UserDefaults.standard.set(false, forKey: "pendingWelcomeCarousel")

        let welcomeVC = OnboardingViewController()
        welcomeVC.modalPresentationStyle = .fullScreen
        welcomeVC.onCompletion = { [weak self] in
            self?.continueOnboardingAfterContacts()
        }
        tabBarController.present(welcomeVC, animated: true)
        Logger.info("Showing welcome carousel for new user")
    }

    /// Builds the tab bar, injects preloaded data into the home screen, installs it
    /// as the window root (with an optional cross-dissolve), then runs post-launch
    /// side effects.
    private func installMainInterface(with data: PreloadedData?, transitionDuration: TimeInterval) {
        let mainTabController = CirclesTabBarController()

        if let data = data,
           let navController = mainTabController.viewControllers?.first as? UINavigationController,
           let circlesVC = navController.topViewController as? CirclesHomeViewController {
            circlesVC.setPreloadedData(data)
        }

        if transitionDuration > 0, window?.rootViewController != nil {
            UIView.transition(with: window!, duration: transitionDuration, options: .transitionCrossDissolve, animations: {
                self.window?.rootViewController = mainTabController
            }, completion: { _ in
                self.runPostLaunchSideEffects()
            })
        } else {
            window?.rootViewController = mainTabController
            DispatchQueue.main.async {
                self.runPostLaunchSideEffects()
            }
        }
    }

    /// Tries to refresh an expired token in place. Logs out ONLY when the server
    /// definitively rejects the token; transient network failures keep the session
    /// so the user isn't kicked to the login screen over a connectivity blip.
    private func revalidateExpiredTokenNonDestructively() {
        AuthService.shared.refreshToken { [weak self] result in
            if case .failure(let error) = result {
                if AuthService.isDefinitiveAuthFailure(error) {
                    Logger.info("Token definitively rejected, starting re-auth flow")
                    DispatchQueue.main.async { self?.handleAutoLogoutAndReauth() }
                } else {
                    Logger.warning("Transient token refresh failure, keeping session: \(error)")
                    // API-level 401 handling covers the case where the token is truly dead
                }
            }
        }
    }

    private func updateRootViewController(isLoggedIn: Bool) {
        if isLoggedIn {
            // Cache-first fast path: if we have cached data (even stale, up to 7 days),
            // install the home screen immediately and refresh silently in the background.
            // The home screen refetches places/connections on appear, so stale content
            // is visible for roughly one network round trip.
            if let cached = PreloadManager.shared.getCachedData(allowStale: true) {
                Logger.info("Cache-first launch: installing home immediately")
                installMainInterface(with: cached, transitionDuration: window?.rootViewController == nil ? 0 : 0.3)
                // The home screen refetches its own content on appear. Rewrite the
                // launch cache only when it has gone stale - a fresh cache makes a
                // background re-run pure duplicate traffic (the requests fire well
                // outside APIService's short GET-dedup window).
                if !PreloadManager.shared.isCacheValid() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        PreloadManager.shared.refreshInBackground()
                    }
                }
                return
            }

            // No usable cache: show splash screen with preloading
            let splashVC = SplashScreenViewController()
            
            // Animate transition if there's an existing view controller
            if window?.rootViewController != nil {
                UIView.transition(with: window!, duration: 0.3, options: .transitionCrossDissolve, animations: {
                    self.window?.rootViewController = splashVC
                }, completion: nil)
            } else {
                window?.rootViewController = splashVC
            }
            
            // Failsafe watchdog: only fires if the preload completion never runs at all.
            // PreloadManager surfaces its own 45s timeout through the failure branch below,
            // so this deadline must stay above that to avoid racing a slow-but-successful load.
            var hasCompleted = false
            let timeoutWorkItem = DispatchWorkItem { [weak self, weak splashVC] in
                guard let self = self, let splashVC = splashVC else { return }
                guard !hasCompleted else { return } // Already completed normally

                Logger.debug("⏰ SceneDelegate: Splash screen timeout reached (60 seconds)")

                // Show error with retry option. A timeout is never an auth failure,
                // so this always offers Retry - the user decides when to give up.
                let alert = UIAlertController(
                    title: "Loading Timeout",
                    message: "The app is taking longer than expected to load. This might be due to network issues.",
                    preferredStyle: .alert
                )

                alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
                    Logger.debug("🔄 User chose to retry from splash screen timeout")
                    self.updateRootViewController(isLoggedIn: true)
                })

                alert.addAction(UIAlertAction(title: "Logout", style: .destructive) { _ in
                    Logger.debug("🚪 User chose to logout from splash screen timeout")
                    AuthService.shared.logout()
                })

                splashVC.present(alert, animated: true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeoutWorkItem)

            // Start preloading all data
            PreloadManager.shared.preloadAllData(
                progressHandler: { progress, status in
                    Logger.debug("🚦 Progress update: \(progress) - \(status)")
                    splashVC.updateProgress(progress, status: status)
                },
                completion: { [weak self] result in
                    hasCompleted = true // Mark as completed to prevent timeout handler
                    timeoutWorkItem.cancel()
                    Logger.debug("🚦 PreloadManager completion called")
                    switch result {
                    case .success(let preloadedData):
                        // Data loaded successfully, show main interface
                        Logger.debug("🚦 Success - showing main interface")
                        DispatchQueue.main.async {
                            guard let self = self else {
                                Logger.debug("❌ Self is nil in completion")
                                return
                            }

                            // Dismiss any watchdog alert still showing so the transition
                            // never happens underneath a live modal
                            splashVC.presentedViewController?.dismiss(animated: false)

                            // Complete splash animation and transition
                            splashVC.completeLoading {
                                self.installMainInterface(with: preloadedData, transitionDuration: 0.5)
                            }
                        }
                        
                    case .failure(let error):
                        // Failed to load data, show error and logout
                        Logger.debug("Failed to preload data: \(error)")

                        guard let self = self else { return }

                        // Check if it's a token expiration error or user not found error
                        let isTokenExpired = (error is AuthError && (error as! AuthError) == .tokenExpired)
                        let isUserNotFound = (error is AuthError && (error as! AuthError) == .userNotFound)

                        // Check for session expired errors from PreloadManager
                        var isSessionExpired = false
                        if let nsError = error as? NSError, nsError.domain == "PreloadManager" {
                            if nsError.code == -2 || nsError.code == -3 {
                                isSessionExpired = true
                            }
                        }

                        // If token expired or session expired, auto-logout and attempt re-auth
                        if isTokenExpired || isUserNotFound || isSessionExpired {
                            Logger.debug("🚪 SceneDelegate: Token/session expired - auto-logging out and attempting re-auth")
                            self.handleAutoLogoutAndReauth()
                        } else {
                            // For other errors, show an alert with retry option.
                            // Network/timeout failures are never auth failures, so
                            // Retry stays available indefinitely - no auto-logout.
                            DispatchQueue.main.async {

                                // Provide more specific error messages
                                var message = "Unable to load your data. Please try again."

                                if let nsError = error as? NSError {
                                    if nsError.domain == "PreloadManager" {
                                        switch nsError.code {
                                        case -1:
                                            message = "Loading is taking longer than expected. This may be due to a slow network connection."
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

                                alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
                                    Logger.debug("🔄 User chose to retry from preload error")
                                    self.updateRootViewController(isLoggedIn: true)
                                })

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
        Logger.debug("📱 SceneDelegate: handleURLContext called with URL: \(url.absoluteString)")
        handleDeepLink(url)
    }
    
    private func handleUniversalLink(_ url: URL) {
        // Handle Universal Links from our backend
        Logger.debug("📱 SceneDelegate: Processing Universal Link with path: \(url.path)")
        
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
                    handleCircleLink(circleId: circleId, url: url)
                }
            case "connect":
                if pathComponents.count >= 3 {
                    let userId = pathComponents[2]
                    stashInviteReferralCode(from: url)
                    handleConnectionInvite(from: userId)
                }
            default:
                Logger.debug("📱 SceneDelegate: Unknown app path: \(appPath)")
            }
        } else if pathComponents.first == "daily-summary" {
            navigateToDailySummary()
        } else if pathComponents.first == "video" && pathComponents.count >= 2 {
            let videoId = pathComponents[1]
            navigateToVideo(videoId: videoId)
        } else if pathComponents.first == "share" && pathComponents.count >= 3 && pathComponents[1] == "video" {
            // Shared moment links (https://<backend>/share/video/<id>) open
            // the moment directly when the app is installed
            let videoId = pathComponents[2]
            navigateToVideo(videoId: videoId)
        } else if pathComponents.first == "circle" && pathComponents.count >= 2 {
            let circleId = pathComponents[1]
            handleCircleLink(circleId: circleId, url: url)
        } else if pathComponents.first == "place" && pathComponents.count >= 2 {
            // Shared place links (https://<backend>/place/<id>?ref=<userId>)
            // open the place directly, carrying share attribution
            let placeId = pathComponents[1]
            let refUserId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "ref" })?.value
            navigateToPlace(placeId: placeId, refUserId: refUserId)
        } else if pathComponents.first == "user" && pathComponents.count >= 2 {
            // Shared profile links (https://<backend>/user/<id>)
            let userId = pathComponents[1]
            navigateToUserProfile(userId: userId)
        } else if pathComponents.first == "connect" && pathComponents.count >= 2 {
            // Shared connect links (https://<backend>/connect/<id>?code=<referral>)
            let userId = pathComponents[1]
            stashInviteReferralCode(from: url)
            handleConnectionInvite(from: userId)
        } else if pathComponents.first == "s" && pathComponents.count >= 2 {
            // Physical sticker QR code: https://<backend>/s/<code>
            let code = pathComponents[1]
            handleStickerCode(code)
        }
    }

    /// Circle universal links may carry a ?share= token granting view access
    /// to private circles — validate it the same way the custom-scheme path
    /// does instead of dropping it
    private func handleCircleLink(circleId: String, url: URL) {
        if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let shareToken = urlComponents.queryItems?.first(where: { $0.name == "share" })?.value {
            handleSharedCircleWithToken(circleId: circleId, shareToken: shareToken)
        } else {
            navigateToCircle(circleId: circleId)
        }
    }
    
    private func handleOpenPath(_ path: String) {
        // Handle specific paths
        if path == "settings/notifications" {
            navigateToNotificationSettings()
        } else if path == "network" || path == "network/find-friends" {
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
            Logger.debug("📱 SceneDelegate: URL scheme '\(url.scheme ?? "nil")' is not 'circles', returning")
            return
        }
        
        Logger.debug("📱 SceneDelegate: Processing deep link with path: \(url.path)")
        Logger.debug("📱 SceneDelegate: Path components: \(url.pathComponents)")
        Logger.debug("📱 SceneDelegate: Path components count: \(url.pathComponents.count)")
        
        // Handle different path components
        let components = url.pathComponents
        
        // Log each component for debugging
        for (index, component) in components.enumerated() {
            Logger.debug("📱 SceneDelegate: Component[\(index)]: '\(component)'")
        }
        
        // Handle deep linking after app is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Logger.debug("📱 SceneDelegate: Inside dispatch queue, processing components")
            
            // First check if this is a host-based URL format (e.g., circles://connect/userId)
            if url.host == "connect" {
                // Handle circles://connect/userId format where "connect" is the host
                Logger.debug("📱 SceneDelegate: Detected 'connect' as host")
                let userId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                Logger.debug("📱 SceneDelegate: Extracted userId from path: \(userId)")
                if !userId.isEmpty {
                    Logger.debug("📱 SceneDelegate: Calling handleConnectionInvite with userId: \(userId)")
                    self.stashInviteReferralCode(from: url)
                    self.handleConnectionInvite(from: userId)
                    return
                }
            }
            
            // Handle video deep links (e.g., circles://video/[videoId])
            if url.host == "video" {
                Logger.debug("📱 SceneDelegate: Detected 'video' as host")
                let videoId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                Logger.debug("📱 SceneDelegate: Extracted videoId from path: \(videoId)")
                if !videoId.isEmpty {
                    Logger.debug("📱 SceneDelegate: Calling handleVideoDeepLink with videoId: \(videoId)")
                    self.handleVideoDeepLink(videoId: videoId)
                    return
                }
            }
            
            // Handle referral deep links (e.g., circles://referral?code=ABC123)
            if url.host == "referral" {
                Logger.debug("📱 SceneDelegate: Detected 'referral' as host")
                if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value {
                    Logger.debug("📱 SceneDelegate: Found referral code: \(code)")
                    self.handleReferralCode(code)
                    return
                }
            }
            
            // Handle sticker deep links (e.g., circles://sticker?code=AB12CD)
            // used by the sticker landing page fallback for in-app browsers
            if url.host == "sticker" {
                Logger.debug("📱 SceneDelegate: Detected 'sticker' as host")
                if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value {
                    Logger.debug("📱 SceneDelegate: Found sticker code: \(code)")
                    self.handleStickerCode(code)
                    return
                }
            }

            // Handle daily summary deep link (e.g., circles://daily-summary)
            if url.host == "daily-summary" {
                Logger.debug("📱 SceneDelegate: Detected 'daily-summary' deep link")
                self.navigateToDailySummary()
                return
            }

            // Handle network deep link (e.g., circles://network) — used by the
            // connection-accepted email's "View Connection" button
            if url.host == "network" {
                Logger.debug("📱 SceneDelegate: Detected 'network' deep link")
                self.navigateToMyNetwork()
                return
            }
            
            // Handle settings/notifications deep link (e.g., circles://settings/notifications)
            if url.host == "settings" && url.path == "/notifications" {
                Logger.debug("📱 SceneDelegate: Detected 'settings/notifications' deep link")
                self.navigateToNotificationSettings()
                return
            }
            
            // Handle circle deep links with share tokens (e.g., circles://circle/circleId?share=shareToken)
            if url.host == "circle" {
                Logger.debug("📱 SceneDelegate: Detected 'circle' as host")
                let circleId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                Logger.debug("📱 SceneDelegate: Extracted circleId from path: \(circleId)")
                
                // Check for share token in query parameters
                if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let shareToken = urlComponents.queryItems?.first(where: { $0.name == "share" })?.value {
                    Logger.debug("📱 SceneDelegate: Found share token: \(shareToken)")
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
                        Logger.debug("📱 SceneDelegate: Found share token in path format: \(shareToken)")
                        self.handleSharedCircleWithToken(circleId: circleId, shareToken: shareToken)
                    } else {
                        self.navigateToCircle(circleId: circleId)
                    }
                } else if components[1] == "share" && components.count >= 4 && components[2] == "circle" {
                    // Example: circles://share/circle/shareId_123
                    let shareId = components[3]
                    self.handleSharedCircle(shareId: shareId)
                } else if components[1] == "place" && components.count >= 3 {
                    // Example: circles://place/place_123?ref=user_456
                    let placeId = components[2]
                    let refUserId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "ref" })?.value
                    self.navigateToPlace(placeId: placeId, refUserId: refUserId)
                } else if components[1] == "user" && components.count >= 3 {
                    // Example: circles://user/user_123
                    let userId = components[2]
                    self.navigateToUserProfile(userId: userId)
                } else if components[1] == "connect" && components.count >= 3 {
                    // Example: circles:///connect/user_123 (with triple slash)
                    let userId = components[2]
                    Logger.debug("📱 SceneDelegate: Handling connection invite from user: \(userId)")
                    self.stashInviteReferralCode(from: url)
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
    
    private func navigateToPlace(placeId: String, refUserId: String? = nil) {
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
                    // Remember who shared this place so they earn points if it gets added
                    if let refUserId = refUserId {
                        RewardsService.shared.storeShareAttribution(
                            googlePlaceId: place.googlePlaceId,
                            refUserId: refUserId
                        )
                    }
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
        captureStickerCodeFromPasteboardIfFirstLaunch()

        // Check for any pending notifications or updates
        if AuthService.shared.isLoggedIn {
            // Clear notification badge when user opens the app
            Logger.debug("🔔 SceneDelegate: Clearing notification badge on app activation")
            NotificationService.shared.clearBadge()

            // Record the app open (throttled inside the service)
            UserService.shared.reportAppOpen()
            
            // Proactively check and refresh token if needed
            if AuthService.shared.isTokenExpired() {
                Logger.debug("🔄 SceneDelegate: Token expired, attempting in-place refresh on scene activation")
                // Refresh in place; only a definitive server rejection logs out
                revalidateExpiredTokenNonDestructively()
            }
            
            // Ensure push token is registered
            if let fcmToken = UserDefaults.standard.string(forKey: "FCMToken") {
                Logger.debug("🎬 ===== SCENE ACTIVE - TOKEN CHECK =====")
                Logger.debug("🎬 Scene became active at: \(Date())")
                Logger.debug("🎬 Found saved FCM token: \(fcmToken.prefix(20))...")
                Logger.debug("🎬 Re-registering token with backend to ensure it's current")
                NotificationService.shared.registerDeviceToken(fcmToken)
            } else {
                Logger.debug("🎬 ===== SCENE ACTIVE - NO TOKEN =====")
                Logger.debug("🎬 Scene became active, but no FCM token saved")
                Logger.debug("🎬 Requesting new FCM token...")
                Messaging.messaging().token { token, error in
                    if let token = token {
                        Logger.debug("🎬 Got new FCM token: \(token.prefix(20))...")
                        NotificationService.shared.registerDeviceToken(token)
                    } else if let error = error {
                        Logger.debug("🎬 Failed to get FCM token: \(error)")
                    }
                }
            }
        }
        
        // Check for app updates
        checkForAppUpdates()
    }
    
    private func handleConnectionInvite(from userId: String) {
        Logger.debug("📱 SceneDelegate: handleConnectionInvite called with userId: \(userId)")
        Logger.debug("📱 SceneDelegate: Current user logged in: \(AuthService.shared.isLoggedIn)")
        Logger.debug("📱 SceneDelegate: Current user ID: \(AuthService.shared.getUserId() ?? "nil")")
        
        // If user is not logged in, store the connection invite and prompt login
        guard AuthService.shared.isLoggedIn else {
            Logger.debug("📱 SceneDelegate: User not logged in, storing pending connection invite")
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
        Logger.debug("📱 SceneDelegate: About to call NetworkManager.handleConnectionInvite")
        NetworkManager.shared.handleConnectionInvite(from: userId) { [weak self] result in
            Logger.debug("📱 SceneDelegate: NetworkManager.handleConnectionInvite callback received")
            DispatchQueue.main.async {
                switch result {
                case .success(let connection):
                    Logger.debug("📱 SceneDelegate: Connection successful! Connection ID: \(connection.id), Status: \(connection.status)")
                    // Refresh connections list to ensure UI is updated
                    NetworkManager.shared.loadConnections()
                    
                    // Navigate to the My Network tab (tab order: 0 Home, 1 My Network, 2 Messages, 3 Me)
                    if let tabBarController = self?.window?.rootViewController as? CirclesTabBarController {
                        tabBarController.selectedIndex = 1 // My Network tab
                        
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
                    Logger.debug("📱 SceneDelegate: Connection failed with error: \(error)")

                    // Say what actually happened. Most of these aren't failures
                    // at all — the invite was declined locally on purpose — so
                    // only genuine errors get the "Connection Failed" title.
                    let title: String
                    let errorMessage: String

                    switch error as? ConnectionInviteError {
                    case .ownInviteLink:
                        title = "That's Your Invite Link"
                        errorMessage = "Share it with someone else — they'll connect with you when they open it."
                    case .alreadyConnected:
                        title = "Already Connected"
                        errorMessage = "You are already connected to this user."
                    case .requestPending:
                        title = "Request Pending"
                        errorMessage = "You already have a connection request with this user."
                    case nil:
                        // Anything else is a real failure. Prefer the server's
                        // own wording when it sent one.
                        title = "Connection Failed"
                        errorMessage = (error as? APIError)?.serverMessage ?? "Failed to send connection request"
                    }

                    let alert = UIAlertController(
                        title: title,
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

        // Single-token links carry no colon-separated payload and would be
        // dropped by the components.count >= 2 parse below
        if pendingLink == "network" || pendingLink == "daily-summary" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if pendingLink == "network" {
                    self.navigateToMyNetwork()
                } else {
                    self.navigateToDailySummary()
                }
            }
            return
        }

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
    
    // (showContactsOnboarding was deleted: the phone-contacts import is gone
    // from the app entirely — invites go out via the share sheet instead.)

    /// Continues the first-launch onboarding chain after the welcome carousel:
    /// notification prompt next (previously an else-if meant brand-new users
    /// saw only one of the steps), then the tutorial.
    private func continueOnboardingAfterContacts() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            if self.shouldShowNotificationOnboarding() {
                // Its onCompletion callback chains into the tutorial
                self.showNotificationOnboarding()
            } else {
                OnboardingManager.shared.checkIfUserNeedsTutorial { needsTutorial in
                    if needsTutorial {
                        OnboardingManager.shared.startTutorial()
                        Logger.info("Starting tutorial after contacts onboarding")
                    }
                }
            }
        }
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
                Logger.debug("🎬 Token needs refresh on foreground, refreshing...")
                AuthService.shared.refreshToken { result in
                    switch result {
                    case .success:
                        Logger.debug("🎬 Token refreshed successfully on foreground")
                    case .failure(let error):
                        Logger.debug("🎬 Token refresh failed on foreground: \(error)")
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
    
    /// Connect invite links can carry the sharer's referral code (?code=XXXXXX).
    /// For a recipient who isn't signed in yet, stash it as the pending referral
    /// code so the Register screen prefills it and applies it after signup.
    /// Logged-in users just get the normal auto-connect — no referral involved.
    private func stashInviteReferralCode(from url: URL) {
        guard !AuthService.shared.isLoggedIn,
              !ReferralService.shared.hasUsedReferralCode(),
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { return }
        Logger.debug("📱 SceneDelegate: Stashing referral code from connect invite: \(code)")
        ReferralService.shared.savePendingReferralCode(code.uppercased())
    }

    private func handleReferralCode(_ code: String) {
        Logger.debug("📱 SceneDelegate: handleReferralCode called with code: \(code)")
        
        // If user is not logged in, save the code for later
        guard AuthService.shared.isLoggedIn else {
            Logger.debug("📱 SceneDelegate: User not logged in, saving referral code for later")
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
            Logger.debug("📱 SceneDelegate: User has already used a referral code")
            
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
    
    // MARK: - Sticker Code Handling

    private func handleStickerCode(_ code: String) {
        Logger.debug("📱 SceneDelegate: handleStickerCode called with code: \(code)")

        // If the user is not logged in, save the code — it's redeemed right
        // after signup/login via runPostLaunchSideEffects (all auth routes)
        guard AuthService.shared.isLoggedIn else {
            Logger.debug("📱 SceneDelegate: User not logged in, saving sticker code for later")
            RewardsService.shared.savePendingStickerCode(code)

            let alert = UIAlertController(
                title: "Rewards Waiting! 🎁",
                message: "Sign up for FavCircles to save this place and earn store points you can use on your next visit.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Sign Up", style: .default) { _ in
                // The auth state listener will handle showing the auth screen
            })
            alert.addAction(UIAlertAction(title: "Later", style: .cancel))

            if let topVC = window?.rootViewController {
                topVC.present(alert, animated: true)
            }
            return
        }

        StickerRewardCoordinator.shared.handleScannedCode(code)
    }

    /// Deferred deep link for store QR codes: the App Store install wipes any
    /// link context, so the sticker landing page copies
    /// "favcircles-sticker:<CODE>" to the clipboard when the visitor taps
    /// Get the App. On the very first activation after install we check the
    /// pasteboard once and stash the code so the normal pending-sticker
    /// redemption picks it up after signup. One-shot by design — the paste
    /// permission prompt must not become a recurring launch experience.
    private func captureStickerCodeFromPasteboardIfFirstLaunch() {
        let checkedKey = "hasCheckedPasteboardForStickerCode"
        guard !UserDefaults.standard.bool(forKey: checkedKey) else { return }
        UserDefaults.standard.set(true, forKey: checkedKey)

        // hasStrings doesn't trigger the paste permission prompt; reading
        // .string does — which is why this whole check is one-shot
        guard UIPasteboard.general.hasStrings,
              let text = UIPasteboard.general.string,
              let match = text.range(of: #"favcircles-sticker:([A-Z0-9]{4,16})"#, options: .regularExpression) else {
            return
        }

        let code = String(text[match].dropFirst("favcircles-sticker:".count))
        Logger.debug("📱 SceneDelegate: Found sticker code on pasteboard from pre-install scan: \(code)")

        // Consume it so a later launch (or another app) doesn't see it
        UIPasteboard.general.items = []

        RewardsService.shared.savePendingStickerCode(code)
        if AuthService.shared.isLoggedIn {
            redeemPendingStickerCodeIfNeeded()
        }
        // Not logged in: redeemPendingStickerCodeIfNeeded runs after every
        // auth route via runPostLaunchSideEffects
    }

    /// Redeems a sticker code that was scanned before the user was logged in.
    /// Runs for every auth route (email + social), unlike the referral replay
    /// which only covers email signup.
    private func redeemPendingStickerCodeIfNeeded() {
        guard AuthService.shared.isLoggedIn,
              let code = RewardsService.shared.getPendingStickerCode() else { return }

        RewardsService.shared.clearPendingStickerCode()
        Logger.debug("📱 SceneDelegate: Redeeming pending sticker code: \(code)")

        // Give the main interface (and any onboarding modals) a moment to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            StickerRewardCoordinator.shared.handleScannedCode(code)
        }
    }

    // MARK: - Video Deep Link Handling
    
    private func handleVideoDeepLink(videoId: String) {
        Logger.debug("📱 SceneDelegate: handleVideoDeepLink called with videoId: \(videoId)")
        
        // If user is not logged in, store the video link and prompt login
        guard AuthService.shared.isLoggedIn else {
            Logger.debug("📱 SceneDelegate: User not logged in, storing pending video link")
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
                    Logger.debug("Failed to load video: \(error)")
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

        Logger.debug("📱 SceneDelegate: Presented DailySummaryViewController from daily-summary deep link")
    }

    /// Switch to the My Network tab (tab order: 0 Home, 1 My Network, 2 Messages, 3 Me)
    private func navigateToMyNetwork() {
        guard AuthService.shared.isLoggedIn,
              let tabBarController = window?.rootViewController as? CirclesTabBarController else {
            // Store the deep link target to navigate after login
            UserDefaults.standard.set("network", forKey: "pendingDeepLink")
            return
        }

        tabBarController.selectedIndex = 1
        Logger.debug("📱 SceneDelegate: Switched to My Network tab from network deep link")
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
        Logger.debug("💎 SceneDelegate: Showing login for promoted purchase")
        
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
                    Logger.debug("💎 Login screen presented for promoted purchase")
                }
            }
        }
    }

    // MARK: - Auto-Logout and Re-authentication

    /// Returns the top-most presented view controller, for presenting alerts
    private func topViewController() -> UIViewController? {
        guard var topController = window?.rootViewController else { return nil }
        while let presented = topController.presentedViewController {
            topController = presented
        }
        return topController
    }

    /// Handles automatic logout after max retry attempts and attempts to re-authenticate for social auth users
    private func handleAutoLogoutAndReauth() {
        Logger.debug("🔐 SceneDelegate: Handling auto-logout and re-authentication")

        // Get the auth provider before logging out
        let authProvider = AuthService.shared.getAuthProvider()
        Logger.debug("🔐 SceneDelegate: Auth provider: \(authProvider ?? "none")")

        // Show a loading message
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Check if we can attempt silent re-authentication
            if let provider = authProvider, provider == "email" {
                // For email/password users, check if biometric is enabled
                if BiometricAuthService.shared.isBiometricLoginEnabled {
                    Logger.debug("🔐 SceneDelegate: Email user with biometric enabled - attempting biometric re-auth")
                    self.attemptEmailBiometricReauth()
                } else {
                    // No biometric - try silent re-login with saved credentials
                    // before falling back to the login screen
                    Logger.debug("🔐 SceneDelegate: Email/password user - attempting silent re-login")
                    self.attemptSilentCredentialReauth()
                }
            } else if let provider = authProvider {
                // For social auth providers, attempt silent re-authentication
                self.attemptSilentReauth(provider: provider)
            } else {
                // No auth provider, just logout
                Logger.debug("🔐 SceneDelegate: No auth provider - logging out")
                AuthService.shared.logout { success in
                    if success {
                        Logger.debug("🔐 SceneDelegate: Logout successful, showing login screen")
                    }
                }
            }
        }
    }

    /// Attempts silent re-authentication for social auth providers
    private func attemptSilentReauth(provider: String) {
        Logger.debug("🔐 SceneDelegate: Attempting silent re-authentication for provider: \(provider)")

        // Show a temporary loading message
        var loadingAlert: UIAlertController?
        if let topController = topViewController() {
            loadingAlert = AlertPresenter.showLoading(
                message: "Please wait while we refresh your session...",
                from: topController
            )
        }

        // Logout first to clear expired session
        AuthService.shared.logout { [weak self] success in
            guard let self = self else { return }

            // Dismiss loading alert, then continue (the next step may present
            // its own alert, so wait for the dismissal to finish)
            DispatchQueue.main.async {
                let continueReauth = {
                    switch provider {
                    case "google":
                        self.attemptGoogleReauth()
                    case "apple":
                        self.attemptAppleReauth()
                    case "facebook":
                        self.attemptFacebookReauth()
                    default:
                        Logger.debug("🔐 SceneDelegate: No silent re-auth available for provider: \(provider)")
                        // Just show login screen
                    }
                }
                if let loadingAlert = loadingAlert {
                    loadingAlert.dismiss(animated: true, completion: continueReauth)
                } else {
                    continueReauth()
                }
            }
        }
    }

    /// Attempts to silently re-authenticate with Google
    private func attemptGoogleReauth() {
        Logger.debug("🔐 SceneDelegate: Attempting Google re-authentication")

        // Show a loading indicator
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            var loadingAlert: UIAlertController?
            if let topController = self.topViewController() {
                loadingAlert = AlertPresenter.showLoading(
                    message: "Signing you back in...",
                    from: topController
                )
            }

            SocialAuthService.shared.restoreGoogleSignInSession { [weak self] result in
                // Dismiss loading alert
                DispatchQueue.main.async {
                    let handleResult = {
                        switch result {
                        case .success:
                            Logger.debug("🔐 SceneDelegate: Google session restored and logged in successfully")
                            // The session is restored and login was triggered
                            // The auth state listener will handle showing the main interface

                        case .failure(let error):
                            Logger.debug("🔐 SceneDelegate: Google re-auth failed: \(error)")
                            // Show a message to the user
                            self?.showReauthFailedMessage()
                        }
                    }
                    if let loadingAlert = loadingAlert {
                        loadingAlert.dismiss(animated: true, completion: handleResult)
                    } else {
                        handleResult()
                    }
                }
            }
        }
    }

    /// Attempts to silently re-authenticate with Apple
    private func attemptAppleReauth() {
        Logger.debug("🔐 SceneDelegate: Apple re-auth not implemented - showing login screen")
        // Apple Sign In doesn't support silent re-authentication
        // User needs to manually sign in again
        showReauthFailedMessage()
    }

    /// Attempts to silently re-authenticate with Facebook
    private func attemptFacebookReauth() {
        Logger.debug("🔐 SceneDelegate: Facebook re-auth not implemented - showing login screen")
        // Facebook re-auth would need to check if there's an active token
        // For now, just show login screen
        showReauthFailedMessage()
    }

    /// Attempts a silent re-login with credentials saved in the keychain (no biometric required)
    private func attemptSilentCredentialReauth() {
        guard let credentials = KeychainManager.shared.retrieveCredentials() else {
            Logger.debug("🔐 SceneDelegate: No saved credentials - logging out")
            AuthService.shared.logout { success in
                if success {
                    Logger.debug("🔐 SceneDelegate: Logout successful, showing login screen")
                }
            }
            return
        }

        Logger.debug("🔐 SceneDelegate: Found saved credentials, attempting silent re-login")
        AuthService.shared.login(email: credentials.email, password: credentials.password) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    Logger.debug("🔐 SceneDelegate: Silent re-login successful")
                    // Auth state listener will refresh the UI
                case .failure(let error):
                    Logger.debug("🔐 SceneDelegate: Silent re-login failed: \(error) - logging out")
                    AuthService.shared.logout { _ in }
                    self?.showReauthFailedMessage()
                }
            }
        }
    }

    /// Attempts to re-authenticate email/password user with biometric
    private func attemptEmailBiometricReauth() {
        Logger.debug("🔐 SceneDelegate: Attempting email biometric re-authentication")

        // Show a loading message
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            var loadingAlert: UIAlertController?
            if let topController = self.topViewController() {
                loadingAlert = AlertPresenter.showLoading(
                    message: BiometricAuthService.shared.getBiometricPrompt(),
                    from: topController
                )
            }

            let finish: (@escaping () -> Void) -> Void = { action in
                DispatchQueue.main.async {
                    if let loadingAlert = loadingAlert {
                        loadingAlert.dismiss(animated: true, completion: action)
                    } else {
                        action()
                    }
                }
            }

            // Logout first to clear expired session
            AuthService.shared.logout { [weak self] success in
                guard let self = self else { return }

                // The biometric keychain read blocks while Face ID is showing,
                // so keep it off the main thread
                DispatchQueue.global(qos: .userInitiated).async {
                    let credentials = KeychainManager.shared.retrieveCredentialsWithBiometric(
                        reason: BiometricAuthService.shared.getBiometricPrompt()
                    )

                    guard let credentials = credentials else {
                        Logger.debug("🔐 SceneDelegate: Failed to retrieve credentials with biometric")
                        finish {
                            self.showReauthFailedMessage()
                        }
                        return
                    }

                    Logger.debug("🔐 SceneDelegate: Retrieved credentials with biometric, attempting login")
                    AuthService.shared.login(email: credentials.email, password: credentials.password) { [weak self] result in
                        finish {
                            switch result {
                            case .success:
                                Logger.debug("🔐 SceneDelegate: Email biometric re-auth successful")
                                // Auth state listener will handle showing main interface

                            case .failure(let error):
                                Logger.debug("🔐 SceneDelegate: Email biometric re-auth failed: \(error)")
                                self?.showReauthFailedMessage()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Shows a message when automatic re-authentication fails
    private func showReauthFailedMessage() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let topController = self.topViewController() else { return }

            AlertPresenter.showError(
                title: "Session Expired",
                message: "Your session has expired. Please log in again to continue.",
                from: topController
            )
        }
    }
}
