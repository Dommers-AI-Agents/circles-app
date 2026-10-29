import UIKit

/// The first-session chain for a fresh signup (name → first people →
/// location → photo map → notifications → home tour) and the
/// notification onboarding later sessions can get. Owned by SceneDelegate.
@MainActor
final class FirstSessionCoordinator: SceneCoordinator {
    weak var host: SceneDelegate?

    init(host: SceneDelegate) {
        self.host = host
    }

    /// Arms the first-session chain for a fresh signup. The welcome carousel
    /// was CUT (Wes, 2026-08-19: "a terrible waste of space") — new users go
    /// straight into the app, and the home-page bubble tour does the teaching.
    /// Chain: home installs → "Your first people" sheet → notification
    /// onboarding → home tour (finishFirstSessionChain).
    func armFirstSessionChain() {
        OnboardingManager.shared.isFirstSessionFlowActive = true
        UserDefaults.standard.set(false, forKey: "pendingWelcomeCarousel")
        Logger.info("First-session chain armed (no carousel)")

        // Failsafe: if any link's completion never fires, isFirstSessionFlowActive
        // sticks and silently suppresses the tour for the whole session. Force
        // the terminal step after 25s; reschedule once if a chain modal is
        // legitimately holding the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            self?.firstSessionFailsafeFired()
        }
    }

    private var firstSessionFailsafeReschedules = 0
    private func firstSessionFailsafeFired() {
        guard OnboardingManager.shared.isFirstSessionFlowActive else { return }
        // A chain screen still up (people / location / notifications) means
        // they're reading, not stuck: keep waiting, up to ~5 minutes
        if window?.rootViewController?.presentedViewController != nil, firstSessionFailsafeReschedules < 12 {
            firstSessionFailsafeReschedules += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
                self?.firstSessionFailsafeFired()
            }
            return
        }
        Logger.warning("⏰ First-session chain stalled — failsafe finishing it")
        finishFirstSessionChain()
    }

    // MARK: - First-session chain (after home installs)

    /// Waits until pendingConnections is trustworthy — the welcome requests
    /// exist server-side before signup even returns, so this is one fetch at
    /// most. A 5s timeout keeps a dead network from stalling onboarding.
    private func ensurePendingConnectionsLoaded(completion: @escaping () -> Void) {
        if !NetworkManager.shared.pendingConnections.isEmpty {
            completion()
            return
        }
        var finished = false
        let finish = { if !finished { finished = true; completion() } }
        NetworkManager.shared.loadConnections { finish() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { finish() }
    }

    /// first-people sheet → notification onboarding → home tour decision.
    /// Runs from runPostLaunchSideEffects when the first-session flow is active.
    func continueFirstSessionAfterCarousel() {
        guard let tabBarController = window?.rootViewController as? CirclesTabBarController else {
            finishFirstSessionChain()
            return
        }
        // "What should friends call you?" first, when signup didn't give a name
        if NameOnboardingViewController.isNeeded {
            let nameVC = NameOnboardingViewController()
            nameVC.onCompletion = { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.presentFirstPeopleSheet(over: tabBarController) }
            }
            nameVC.modalPresentationStyle = .fullScreen
            var presenter: UIViewController = tabBarController
            while let presented = presenter.presentedViewController { presenter = presented }
            presenter.present(nameVC, animated: true)
        } else {
            presentFirstPeopleSheet(over: tabBarController)
        }
    }

    /// Step 2: the "Explore other people's maps" sheet, then location.
    private func presentFirstPeopleSheet(over tabBarController: CirclesTabBarController) {
        ensurePendingConnectionsLoaded { [weak self] in
            guard let self = self else { return }
            var presenter: UIViewController = tabBarController
            while let presented = presenter.presentedViewController { presenter = presented }
            let presented = WelcomeConnectionsViewController.presentIfNeeded(from: presenter) { [weak self] in
                self?.continueOnboardingAfterContacts()
            }
            if !presented {
                self.continueOnboardingAfterContacts()
            }
        }
    }

    /// Terminal step of the first-session chain: one decision function —
    /// home's checkTutorialAndOverlay — picks tutorial vs. suggested-users
    /// overlay, now that the chain's modals are done.
    private func finishFirstSessionChain() {
        let wasActive = OnboardingManager.shared.isFirstSessionFlowActive
        OnboardingManager.shared.isFirstSessionFlowActive = false
        guard wasActive,
              let tabBarController = window?.rootViewController as? CirclesTabBarController,
              let navController = tabBarController.viewControllers?.first as? UINavigationController,
              let homeVC = navController.viewControllers.first as? CirclesHomeViewController else {
            // Home unreachable — fall back to the legacy direct check
            if wasActive {
                OnboardingManager.shared.checkIfUserNeedsTutorial { needsTutorial in
                    if needsTutorial { OnboardingManager.shared.startTutorial() }
                }
            }
            return
        }
        homeVC.checkTutorialAndOverlay()
    }

    // (showContactsOnboarding was deleted: the phone-contacts import is gone
    // from the app entirely — invites go out via the share sheet instead.)

    /// After the first-people sheet: location (Wes, 2026-10-09 — it powers
    /// the map, nearby, weather and more), then notifications, then the tour.
    private func continueOnboardingAfterContacts() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            guard LocationOnboardingViewController.isNeeded,
                  let tabBarController = self.window?.rootViewController as? CirclesTabBarController else {
                self.continueOnboardingAfterLocation()
                return
            }
            let locationVC = LocationOnboardingViewController()
            locationVC.onCompletion = { [weak self] in self?.continueOnboardingAfterLocation() }
            let nav = UINavigationController(rootViewController: locationVC)
            nav.modalPresentationStyle = .fullScreen
            var presenter: UIViewController = tabBarController
            while let presented = presenter.presentedViewController { presenter = presented }
            presenter.present(nav, animated: true)
        }
    }

    /// After location: "Fill your map from your photos" (Wes, 2026-10-16),
    /// once, during the first session; then notifications.
    private func continueOnboardingAfterLocation() {
        guard OnboardingManager.shared.isFirstSessionFlowActive, PhotoMapOnboardingViewController.isNeeded,
              let tabBarController = window?.rootViewController as? CirclesTabBarController else {
            return continueOnboardingAfterPhotoMap()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            let photoVC = PhotoMapOnboardingViewController()
            photoVC.onCompletion = { [weak self] in self?.continueOnboardingAfterPhotoMap() }
            let nav = UINavigationController(rootViewController: photoVC)
            nav.modalPresentationStyle = .fullScreen
            var presenter: UIViewController = tabBarController
            while let presented = presenter.presentedViewController { presenter = presented }
            presenter.present(nav, animated: true)
        }
    }

    private func continueOnboardingAfterPhotoMap() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.shouldShowNotificationOnboarding { [weak self] show in
                guard let self = self else { return }
                self.continueOnboardingAfterLocation(showNotifications: show)
            }
        }
    }

    private func continueOnboardingAfterLocation(showNotifications: Bool) {
        if showNotifications {
            // Its onCompletion callback ends the chain
            showNotificationOnboarding()
        } else if OnboardingManager.shared.isFirstSessionFlowActive {
            finishFirstSessionChain()
        } else {
            OnboardingManager.shared.checkIfUserNeedsTutorial { needsTutorial in
                if needsTutorial {
                    OnboardingManager.shared.startTutorial()
                    Logger.info("Starting tutorial after onboarding")
                }
            }
        }
    }

    /// Not yet shown on this install and notifications aren't already on.
    /// Answers on the main queue (it used to block the main thread on a
    /// semaphore while iOS looked the setting up).
    func shouldShowNotificationOnboarding(_ completion: @escaping (Bool) -> Void) {
        guard !UserDefaults.standard.bool(forKey: "hasShownNotificationOnboarding") else { completion(false); return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let enabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            DispatchQueue.main.async { completion(!enabled) }
        }
    }
    
    func showNotificationOnboarding() {
        guard let tabBarController = window?.rootViewController as? CirclesTabBarController else { return }
        
        Logger.info("Showing notification onboarding")
        
        // Create notification onboarding view controller
        let notificationVC = NotificationOnboardingViewController()
        
        // Configure completion callback
        notificationVC.onCompletion = { [weak self] in
            if OnboardingManager.shared.isFirstSessionFlowActive {
                // First-session chain: one terminal decision (tutorial vs
                // suggested-users overlay) via home's checkTutorialAndOverlay
                self?.finishFirstSessionChain()
            } else {
                // Check if user needs tutorial after notification onboarding
                OnboardingManager.shared.checkIfUserNeedsTutorial { needsTutorial in
                    if needsTutorial {
                        OnboardingManager.shared.startTutorial()
                        Logger.info("Starting tutorial after notification onboarding")
                    }
                }
            }
        }
        
        // Present in navigation controller
        let navController = UINavigationController(rootViewController: notificationVC)
        navController.modalPresentationStyle = .fullScreen
        
        // Present from the tab bar controller
        tabBarController.present(navController, animated: true)
    }
}
