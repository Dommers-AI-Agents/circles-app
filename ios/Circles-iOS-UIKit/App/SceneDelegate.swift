import UIKit
import FavWidgets
import CoreLocation
import CoreSpotlight
import FacebookCore
import FirebaseMessaging

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var authListenerId = "SceneDelegate"

    // Helpers this scene owns; each reads the window back through `host`
    lazy var deepLinks = DeepLinkCoordinator(host: self)
    lazy var inviteLinks = InviteLinkHandler(host: self)
    lazy var firstSession = FirstSessionCoordinator(host: self)
    lazy var shareHandoff = ShareHandoffCoordinator(host: self)
    lazy var rewardCodes = RewardCodeHandler(host: self)
    lazy var reauth = ReauthCoordinator(host: self)

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
        
        // Home Screen quick action on a cold start: stash it like any other
        // pending link; runPostLaunchSideEffects replays it once the tab bar
        // is up
        if let shortcut = connectionOptions.shortcutItem,
           let pending = QuickCheckInShortcutPlanner.pendingLink(forShortcutType: shortcut.type,
                                                                 userInfo: shortcut.userInfo) {
            UserDefaults.standard.set(pending, forKey: "pendingDeepLink")
        }

        // Check if there's a deep link to handle
        if let url = connectionOptions.urlContexts.first?.url {
            Logger.debug("SceneDelegate: URL received on launch: \(url.absoluteString)")

            if url.isFileURL {
                // Export file opened with Circles at cold launch — wait for the
                // main interface to be installed before presenting the import flow
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.deepLinks.handleImportFile(url)
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
                deepLinks.handleDeepLink(url)
            }
        }

        // Universal links (https://api.favcircles.com/…) and Spotlight taps
        // that LAUNCH the app arrive here, not in scene(_:continue:) — they
        // were dropped, so a widget link from a closed app opened Home (Wes,
        // 2026-10-06). The same handler stashes them as pendingDeepLink while
        // the tab bar isn't up yet; they're replayed once it is.
        if let activity = connectionOptions.userActivities.first {
            self.scene(scene, continue: activity)
        }
        
        // App Clip handoff: if the clip left credentials in the shared keychain
        // mailbox, adopt them BEFORE any auth-state read so first launch lands
        // logged in. isLoggedIn reads the keychain live, so ordering is all
        // that matters here.
        rewardCodes.adoptAppClipSessionIfPresent()

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
                reauth.revalidateExpiredTokenNonDestructively()
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
                deepLinks.handleImportFile(url)
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
            deepLinks.handleDeepLink(url)
        }
    }
    
    // Handle Universal Links
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        Logger.debug("📱 SceneDelegate: continue userActivity called")

        // Spotlight result tapped: route into the normal place-detail flow
        if userActivity.activityType == CSSearchableItemActionType {
            if let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
               let placeId = SpotlightIndexService.placeId(fromSpotlightIdentifier: identifier) {
                Logger.debug("📱 SceneDelegate: Spotlight tap for place \(placeId)")
                deepLinks.navigateToPlace(placeId: placeId, refUserId: nil)
            }
            return
        }

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
        if let host = url.host, DeepLinkRouter.universalLinkHosts.contains(host) {
            deepLinks.handleUniversalLink(url)
        }
    }
    
    /// Post-launch side effects that must run once the main interface is installed,
    /// regardless of whether launch went through the splash screen or the cache-first
    /// fast path: pending deep links, connection invites, onboarding, and tutorial.
    private func runPostLaunchSideEffects() {
        deepLinks.handlePendingDeepLink()
        NetworkManager.shared.processPendingConnectionInvite()
        rewardCodes.redeemPendingStickerCodeIfNeeded()
        reauth.offerPasskeySetupIfPending()

        // Quietly locate any imported places still waiting on a coordinate
        // (rows past the import flow's inline-resolution cap)
        ImportResolutionQueue.shared.kick()
        // …and give imported places without a photo a free Apple Look Around one
        ImportPhotoQueue.shared.kick()

        // Mirror saved places into iOS system search (once per session)
        SpotlightIndexService.shared.refreshIndexIfNeeded()

        // Feed the home-screen widget its snapshot
        WidgetSnapshotService.shared.refresh()

        #if DEBUG
        // Debug relay: mirror the share extension's diagnostics dump into
        // Documents, the one place reliably pullable from a Mac via
        // devicectl (the group container itself is not).
        if let debugJSON = UserDefaults(suiteName: ExtensionAuthMailbox.appGroupId)?
            .string(forKey: "shareExt.debug"),
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? debugJSON.data(using: .utf8)?
                .write(to: docs.appendingPathComponent("share-debug.json"), options: [.atomic])
        }
        #endif

        // Sessions that predate the extension auth mirror get one now
        if AuthService.shared.isLoggedIn {
            KeychainService.shared.syncExtensionAuthMailbox()
        }

        // Plan-limit upgrade requested from the share extension: paywall over
        // whatever the share drain below pushes — dismissing the paywall
        // lands the user on the prefilled Add Place, ready to finish.
        let upgradeRequested = AuthService.shared.isLoggedIn && PendingUpgradeMailbox.take()

        // A share the extension parked (logged out / offline at share time)
        shareHandoff.drainPendingShareIfNeeded()

        if upgradeRequested {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.deepLinks.presentUpgradePaywall()
            }
        }

        // "View in FavCircles" tapped in the share extension: go straight to
        // the place they just saved. On a cold launch the root tab bar may
        // not be installed yet — retry briefly instead of silently deferring
        // to the next launch.
        if AuthService.shared.isLoggedIn, let placeId = PendingOpenPlaceMailbox.take() {
            deepLinks.navigateToPlaceWhenReady(placeId, attempts: 6)
        }
        // A whole Google Maps list imported from the share extension → land
        // on the circle it became.
        if AuthService.shared.isLoggedIn, let circleId = PendingOpenCircleMailbox.take() {
            deepLinks.navigateToCircleWhenReady(circleId, attempts: 6)
        }

        if OnboardingManager.shared.isFirstSessionFlowActive {
            // Brand-new signup: no carousel (cut 2026-08-19) — go straight to
            // the chain: name → first-people sheet → location → notifications → home tour.
            // (Contacts onboarding was intentionally cut from first-run —
            // Find Contacts lives in the My Network tab.)
            firstSession.continueFirstSessionAfterCarousel()
        } else {
            firstSession.shouldShowNotificationOnboarding { [weak self] show in
                if show {
                    self?.firstSession.showNotificationOnboarding()
                } else {
                    OnboardingManager.shared.checkIfUserNeedsTutorial { needsTutorial in
                        if needsTutorial {
                            OnboardingManager.shared.startTutorial()
                            Logger.info("New user detected - starting onboarding tutorial")
                        }
                    }
                }
            }
        }
    }

    /// The preload result → root-swap/error handling, shared by the live
    /// completion and the stashed-outcome path.
    private func handlePreloadOutcome(_ result: Result<PreloadedData, Error>, splashVC: SplashScreenViewController?) {
        switch result {
        case .success(let preloadedData):
            Logger.debug("🚦 Success - showing main interface")
            // Dismiss any watchdog alert still showing so the transition
            // never happens underneath a live modal
            splashVC?.presentedViewController?.dismiss(animated: false)
            if let splashVC = splashVC {
                splashVC.completeLoading {
                    self.installMainInterface(with: preloadedData, transitionDuration: 0.5)
                }
            } else {
                installMainInterface(with: preloadedData, transitionDuration: 0.5)
            }

        case .failure(let error):
            Logger.debug("Failed to preload data: \(error)")

            let isTokenExpired = (error is AuthError && (error as! AuthError) == .tokenExpired)
            let isUserNotFound = (error is AuthError && (error as! AuthError) == .userNotFound)
            var isSessionExpired = false
            if let nsError = error as? NSError, nsError.domain == "PreloadManager" {
                if nsError.code == -2 || nsError.code == -3 {
                    isSessionExpired = true
                }
            }

            if isTokenExpired || isUserNotFound || isSessionExpired {
                Logger.debug("🚪 SceneDelegate: Token/session expired - auto-logging out and attempting re-auth")
                reauth.handleAutoLogoutAndReauth()
            } else {
                // For other errors, show an alert with retry option.
                // Network/timeout failures are never auth failures, so
                // Retry stays available indefinitely - no auto-logout.
                var message = "Unable to load your data. Please try again."
                if NetworkErrorClassifier.isConnectivityFailure(error) {
                    message = "Can't reach FavCircles. Check your connection and try again."
                } else if let nsError = error as? NSError {
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

                if let presenter = splashVC ?? window?.rootViewController {
                    AlertPresenter.showAlert(title: "Loading Error", message: message, actions: [
                        ("Retry", .default, {
                            Logger.debug("🔄 User chose to retry from preload error")
                            self.updateRootViewController(isLoggedIn: true)
                        }),
                        ("Logout", .destructive, { AuthService.shared.logout() })
                    ], from: presenter)
                }
            }
        }
    }

    /// Builds the tab bar, injects preloaded data into the home screen, installs it
    /// as the window root (with an optional cross-dissolve), then runs post-launch
    /// side effects.
    private func installMainInterface(with data: PreloadedData?, transitionDuration: TimeInterval) {
        // Before home's people row is built, so it paints these immediately
        if let data {
            NetworkManager.shared.seedConnectionsFromLaunchCache(data.connections)
            // …and their faces, from disk, before the row's first frame
            ImageService.shared.warmProfileImages(data.connections.compactMap(\.connectedUser))
        }
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

    private func updateRootViewController(isLoggedIn: Bool) {
        // Already signed in and on the main tabs: a repeat "signed in" (the
        // Google session restore runs a full sign-in in the background ~4 s
        // after launch) must not rebuild home. It used to install a second
        // home screen that reloaded everything — the spinners and the "loads
        // twice" on cold start (Wes, 2026-10-02).
        if isLoggedIn, window?.rootViewController is CirclesTabBarController {
            Logger.debug("Auth: already signed in on the main tabs, keeping the current home")
            return
        }
        if isLoggedIn {
            // Brand-new signup: force the splash path even if a cache exists,
            // so the first-session chain arms before home is ever visible
            let isFreshSignup = UserDefaults.standard.bool(forKey: "pendingWelcomeCarousel")

            // Cache-first fast path: if we have cached data (even stale, up to 7 days),
            // install the home screen immediately and refresh silently in the background.
            // The home screen refetches places/connections on appear, so stale content
            // is visible for roughly one network round trip.
            if !isFreshSignup, let cached = PreloadManager.shared.getCachedData(allowStale: true) {
                Logger.info("Cache-first launch: installing home immediately")
                installMainInterface(with: cached, transitionDuration: window?.rootViewController == nil ? 0 : 0.3)
                // The home screen refetches its own content on appear. Rewrite the
                // launch cache only when it has gone stale - a fresh cache makes a
                // background re-run pure duplicate traffic (the requests fire well
                // outside APIService's short GET-dedup window).
                if !PreloadManager.shared.isCacheValid() || cached.isMissingFeeds {
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
                }, completion: { _ in
                    if isFreshSignup { self.firstSession.armFirstSessionChain() }
                })
            } else {
                window?.rootViewController = splashVC
                if isFreshSignup { self.firstSession.armFirstSessionChain() }
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
                AlertPresenter.showAlert(
                    title: "Loading Timeout",
                    message: "The app is taking longer than expected to load. This might be due to network issues.",
                    actions: [
                        ("Retry", .default, {
                            Logger.debug("🔄 User chose to retry from splash screen timeout")
                            self.updateRootViewController(isLoggedIn: true)
                        }),
                        ("Logout", .destructive, {
                            Logger.debug("🚪 User chose to logout from splash screen timeout")
                            AuthService.shared.logout()
                        })
                    ],
                    from: splashVC.presentedViewController ?? splashVC)
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
                    DispatchQueue.main.async {
                        guard let self = self else {
                            Logger.debug("❌ Self is nil in completion")
                            return
                        }
                        self.handlePreloadOutcome(result, splashVC: splashVC)
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
        deepLinks.handleDeepLink(url)
    }

    // Entry points other screens and AppDelegate call
    func handleDeepLink(_ url: URL) { deepLinks.handleDeepLink(url) }
    func navigateToUserProfile(userId: String) { deepLinks.navigateToUserProfile(userId: userId) }
    func navigateToVideo(videoId: String) { deepLinks.navigateToVideo(videoId: videoId) }
    func navigateToMeTab() { deepLinks.navigateToMeTab() }
    func showMilestone(_ milestone: PushMilestone) { deepLinks.showMilestone(milestone) }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // Release any resources associated with this scene
        AuthService.shared.removeAuthStateListener(id: authListenerId)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        rewardCodes.captureStickerCodeFromPasteboardIfFirstLaunch()
        // A store QR opened from the background or a cold launch
        rewardCodes.redeemPendingStickerCodeIfNeeded()
        // Signed out: the scan's "Rewards Waiting!" prompt, if a system alert held it back
        if rewardCodes.rewardsPromptOwed { rewardCodes.presentRewardsWaitingPrompt() }
        // A run's lock-screen display left over from a run the app lost (killed mid-run)
        if #available(iOS 16.2, *) {
            RunLiveActivityController.shared.endStaleActivities()
            // Event lock-screen displays outlive the app: keep their push tokens reaching the server
            EventLiveActivityController.shared.resumeWatchingTokens()
            // Signed in since launch: the How Are You? push-to-start token reaches the server
            if #available(iOS 17.2, *) { CareLiveActivityController.shared.uploadStartTokenIfNeeded() }
            // The workout's lock-screen display back in step with the saved workout
            Task { await WorkoutLiveActivityController.shared.reconcile() }
        }

        // Check for any pending notifications or updates
        if AuthService.shared.isLoggedIn {
            // Re-sync the badge with what is actually waiting, rather than
            // blanket-zeroing it. Clearing unconditionally cut both ways: an
            // ephemeral banner's badge did go away, but so did a real one —
            // open the app with three unread messages and the icon went to 0
            // while the messages sat there unread.
            Logger.debug("🔔 SceneDelegate: Syncing notification badge on app activation")
            NotificationService.shared.syncBadge()
            NotificationService.shared.reportPushStatus()

            // Record the app open (throttled inside the service)
            UserService.shared.reportAppOpen()
            
            // Proactively check and refresh token if needed
            if AuthService.shared.isTokenExpired() {
                Logger.debug("🔄 SceneDelegate: Token expired, attempting in-place refresh on scene activation")
                // Refresh in place; only a definitive server rejection logs out
                reauth.revalidateExpiredTokenNonDestructively()
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
        returnToSleepSoundsIfPlaying()
        topUpMotivationReminders()

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

    /// The Motivation coach's notifications are scheduled a few days ahead (each with
    /// its own line), so every return to the app rolls the window forward.
    private func topUpMotivationReminders() {
        guard AuthService.shared.isLoggedIn, let userId = KeychainService.shared.getUserId() else { return }
        Task {
            await MotivationReminderScheduler.refresh(store: AppWidgetHost.makeDataStore(userId: userId),
                                                      quietHours: AppWidgetHost.accountQuietHours)
        }
    }

    /// Sleep Sounds is playing and the person just came back to the app —
    /// almost always by tapping the Now Playing tile, which opens the app but
    /// says nothing about where. Land on the sound so it can be turned off.
    /// The rule itself is `NowPlayingReturnGate`; this only gathers the facts.
    private func returnToSleepSoundsIfPlaying() {
        let tabBar = window?.rootViewController as? CirclesTabBarController
        let nav = tabBar?.viewControllers?.first as? UINavigationController
        let topWidget = tabBar?.selectedIndex == 0
            ? (nav?.topViewController as? HomeWidgetDetailViewController)?.widgetId : nil
        let context = NowPlayingReturnGate.Context(
            isPlaying: SleepSoundEngine.shared.isPlaying,
            isSignedIn: AuthService.shared.isLoggedIn,
            hasModal: tabBar?.presentedViewController != nil,
            topWidgetId: topWidget
        )
        guard NowPlayingReturnGate.shouldOpenSleepSounds(context) else { return }
        deepLinks.navigateToWidget(id: NowPlayingReturnGate.sleepSoundsId)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Refresh the home-screen widget with whatever the session just saw.
        WidgetSnapshotService.shared.refresh()
        // And the icon's long-press "Check in at <place>" rows, from wherever
        // the user ended up during the session
        QuickCheckInShortcuts.updateFromCache()
    }

    /// Home Screen quick action while the app is already running (warm
    /// launch). Same stash format as the cold-start path, replayed at once.
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        guard let pending = QuickCheckInShortcutPlanner.pendingLink(forShortcutType: shortcutItem.type,
                                                                    userInfo: shortcutItem.userInfo) else {
            completionHandler(false)
            return
        }
        UserDefaults.standard.set(pending, forKey: "pendingDeepLink")
        deepLinks.handlePendingDeepLink()
        completionHandler(true)
    }
    
    // MARK: - Promoted Purchase Handling
    
    private func setupPromotedPurchaseNotifications() {
        // Handle login required for promoted purchase
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowLoginForPromotedPurchase),
            name: .showLoginForPromotedPurchase,
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
}
