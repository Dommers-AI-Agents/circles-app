import UIKit

/// The side effects of a link: `Logic/DeepLinkRouter` decides WHERE a
/// universal / custom-scheme / pending link goes; this performs it (tab
/// switches, pushes, presentations), or stashes it as `pendingDeepLink`
/// when the tab bar isn't up yet. Owned by SceneDelegate.
@MainActor
final class DeepLinkCoordinator: SceneCoordinator {
    weak var host: SceneDelegate?

    init(host: SceneDelegate) {
        self.host = host
    }

    /// Handles a place-export file opened with Circles (Mapstr GeoJSON from
    /// Mail, Google Takeout CSV from Files). Copies it out of the inbox and
    /// presents the import flow.
    func handleImportFile(_ url: URL) {
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

    /// Universal link https://api.favcircles.com/app/import — opens the place
    /// import flow directly (same gate and presentation as opening an export
    /// file with the app).
    func presentImportFlow() {
        guard let tabBarController = window?.rootViewController as? CirclesTabBarController else { return }
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
        presenter.present(navController, animated: true)
    }

    /// Universal links (https://api.favcircles.com/…). `DeepLinkRouter` decides
    /// WHERE (unit tested); `route(_:)` decides HOW.
    func handleUniversalLink(_ url: URL) {
        Logger.debug("📱 SceneDelegate: Processing Universal Link with path: \(url.path)")
        guard let destination = DeepLinkRouter().destination(for: url) else {
            Logger.debug("📱 SceneDelegate: Unknown universal link path: \(url.path)")
            return
        }
        route(destination)
    }

    /// Custom-scheme links (circles://…).
    func handleDeepLink(_ url: URL) {
        guard url.scheme == DeepLinkRouter.customScheme else {
            Logger.debug("📱 SceneDelegate: URL scheme '\(url.scheme ?? "nil")' is not 'circles', returning")
            return
        }
        Logger.debug("📱 SceneDelegate: Processing deep link with path: \(url.path)")
        guard let destination = DeepLinkRouter().destination(for: url) else {
            Logger.debug("📱 SceneDelegate: Unrecognized deep link: \(url.absoluteString)")
            return
        }
        // Scheme links can arrive before the interface is fully up — give it a beat
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.route(destination)
        }
    }

    /// Presentation for a parsed link.
    func route(_ destination: DeepLinkDestination) {
        switch destination {
        case .dailySummary:
            navigateToDailySummary()
        case .video(let id, let promptsLogin):
            if promptsLogin { handleVideoDeepLink(videoId: id) } else { navigateToVideo(videoId: id) }
        case .circle(let id, let shareToken):
            // A ?share= token grants view access to a private circle —
            // validate it instead of dropping it
            if let shareToken {
                host?.inviteLinks.handleSharedCircleWithToken(circleId: id, shareToken: shareToken)
            } else {
                navigateToCircle(circleId: id)
            }
        case .sharedCircle(let shareId):
            host?.inviteLinks.handleSharedCircle(shareId: shareId)
        case .place(let id, let refUserId):
            navigateToPlace(placeId: id, refUserId: refUserId)
        case .placeFromExtension(let id):
            // The share extension writes the pending-open mailbox as a
            // fallback before trying this deep link — consume it so the
            // next cold launch doesn't navigate here a second time
            _ = PendingOpenPlaceMailbox.take()
            navigateToPlace(placeId: id)
        case .userProfile(let id):
            navigateToUserProfile(userId: id)
        case .connectionInvite(let userId, let referralCode, let inviteToken):
            host?.inviteLinks.stashInviteReferralCode(referralCode)
            host?.inviteLinks.handleConnectionInvite(from: userId, inviteToken: inviteToken)
        case .importFlow:
            // Shared from Help → Importing Your Places; receivers without
            // the app get the website guide via the backend redirect
            presentImportFlow()
        case .allPlacesMap(let focusCategory):
            // Weekly map-digest email: the user's own map, focused on the
            // emailed category when one rides along
            navigateToAllPlacesMap(focusCategory: focusCategory)
        case .notificationSettings:
            navigateToNotificationSettings()
        case .network:
            selectTabOrStash(index: 1, pendingKey: "network")
        case .addPlace:
            openAddPlaceFlow()
        case .checkIn:
            // Same path as the Home Screen "Check In" action, stashed on cold start
            guard window?.rootViewController is CirclesTabBarController else {
                UserDefaults.standard.set("check-in", forKey: "pendingDeepLink")
                return
            }
            NotificationCenter.default.post(name: .navigateToCheckIn, object: nil)
        case .meTab:
            // Business/claim emails: venue management lives on the Me tab
            selectTabOrStash(index: 3, pendingKey: "me")
        case .piggyBank:
            navigateToCreateWallet()
        case .widget(let id):
            // navigateToWidget stashes to pendingDeepLink when the tab bar
            // isn't up yet or nobody is signed in — which is the normal case
            // for a shared link, since it usually arrives on a cold launch.
            navigateToWidget(id: id)
        case .quote(let id):
            navigateToWidget(id: "quotes", quoteId: id)
        case .workout(let token):
            navigateToWidget(id: "workouts", workoutPostId: token)
        case .postcardShare(let token):
            navigateToWidget(id: "postcard", postcardShareToken: token)
        case .eventInvite(let token):
            navigateToWidget(id: "events", eventToken: token)
        case .homeTab(let segment):
            navigateToHomeTab(segment)
        case .eventOpen(let id):
            navigateToWidget(id: "events", eventId: id)
        case .clubJoin(let token):
            navigateToWidget(id: "clubs", clubToken: token)
        case .clubOpen(let id):
            navigateToWidget(id: "clubs", clubId: id)
        case .dogPost(let id):
            navigateToWidget(id: "dogs", dogPostId: id)
        case .dailyDog(let id):
            navigateToWidget(id: "dogs", dailyDogId: id)
        case .runJoin(let token):
            navigateToWidget(id: "run", runToken: token)
        case .referral(let code):
            host?.inviteLinks.handleReferralCode(code)
        case .sticker(let code):
            host?.rewardCodes.handleStickerCode(code)
        case .upgradePaywall:
            // The share extension's "Upgrade in FavCircles" path (IAP can't
            // run in extensions). Consume the mailbox flag so the next cold
            // launch doesn't present the paywall a second time.
            _ = PendingUpgradeMailbox.take()
            presentUpgradePaywall()
        }
    }

    /// Email CTAs can land on a cold start before the interface is up —
    /// stash the target so the link survives (it used to be dropped silently).
    private func selectTabOrStash(index: Int, pendingKey: String) {
        guard let tabBarController = window?.rootViewController as? CirclesTabBarController else {
            UserDefaults.standard.set(pendingKey, forKey: "pendingDeepLink")
            return
        }
        tabBarController.selectedIndex = index
    }

    /// Welcome-email CTA: open the Add Place flow directly
    private func openAddPlaceFlow() {
        guard let tabBarController = window?.rootViewController as? CirclesTabBarController else {
            UserDefaults.standard.set("add-place", forKey: "pendingDeepLink")
            return
        }
        tabBarController.selectedIndex = 0 // Home tab
        if let navController = tabBarController.viewControllers?.first as? UINavigationController,
           let homeVC = navController.viewControllers.first as? CirclesHomeViewController {
            navController.popToRootViewController(animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                homeVC.quickAddPlaceButtonTapped()
            }
        }
    }

    func navigateToCircle(circleId: String, isSharedViaLink: Bool = false) {
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

    func navigateToPlace(placeId: String, refUserId: String? = nil) {
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

    func navigateToUserProfile(userId: String) {
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

    func handlePendingDeepLink() {
        guard let pendingLink = UserDefaults.standard.string(forKey: "pendingDeepLink") else { return }

        // Clear the pending link
        UserDefaults.standard.removeObject(forKey: "pendingDeepLink")

        // Malformed or unknown links navigate nowhere (see PendingLinkParser)
        guard let link = PendingLinkParser.parse(pendingLink) else { return }

        // Add a delay to ensure the UI is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            switch link {
            case .network: self.navigateToMyNetwork()
            case .dailySummary: self.navigateToDailySummary()
            case .allPlacesMap: self.navigateToAllPlacesMap()
            case .createWallet: self.navigateToCreateWallet()
            case .widget(let id): self.navigateToWidget(id: id)
            case .quote(let id): self.navigateToWidget(id: "quotes", quoteId: id)
            case .workout(let token): self.navigateToWidget(id: "workouts", workoutPostId: token)
            case .postcardOrder(let id): self.navigateToWidget(id: "postcard", postcardOrderId: id)
            case .motivationSend(let lineId): self.navigateToWidget(id: "motivation", motivationLineId: lineId, motivationSend: true)
            case .postcardShare(let token): self.navigateToWidget(id: "postcard", postcardShareToken: token)
            case .eventInvite(let token): self.navigateToWidget(id: "events", eventToken: token)
            case .eventOpen(let id): self.navigateToWidget(id: "events", eventId: id)
            case .clubJoin(let token): self.navigateToWidget(id: "clubs", clubToken: token)
            case .clubOpen(let id, let postId): self.navigateToWidget(id: "clubs", clubId: id, clubPostId: postId)
            case .dogPost(let id): self.navigateToWidget(id: "dogs", dogPostId: id)
            case .dailyDog(let id): self.navigateToWidget(id: "dogs", dailyDogId: id)
            case .runOpen(let id): self.navigateToWidget(id: "run", runId: id)
            case .runJoin(let token): self.navigateToWidget(id: "run", runToken: token)
            case .careAnswer(let askId): self.navigateToWidget(id: "howareyou", careAskId: askId)
            case .fridgeMailCard(let id): self.navigateToWidget(id: "fridgemail", fridgeMailCardId: id)
            case .storeOrder(let id): NotificationCenter.default.post(name: .navigateToStoreOrder, object: id)
            case .venueOrders(let venueId): NotificationCenter.default.post(name: .navigateToVenueOrders, object: venueId)
            case .homeTab(let segment): self.navigateToHomeTab(segment)
            case .openPath(let path):
                if let destination = DeepLinkRouter().openPathDestination(path) { self.route(destination) }
            case .shareToken(let circleId, let shareToken):
                self.host?.inviteLinks.handleSharedCircleWithToken(circleId: circleId, shareToken: shareToken)
            case .circle(let id): self.navigateToCircle(circleId: id)
            case .place(let id): self.navigateToPlace(placeId: id)
            case .user(let id): self.navigateToUserProfile(userId: id)
            case .share(let id): self.host?.inviteLinks.handleSharedCircle(shareId: id)
            case .connect(let fromUserId): self.host?.inviteLinks.handleConnectionInvite(from: fromUserId)
            case .video(let id): self.navigateToVideo(videoId: id)
            case .notificationSettings: self.navigateToNotificationSettings()
            case .milestone(let milestone): self.showMilestone(milestone)
            case .checkIn(let id):
                // Cold-start tap on the "you're near <place>" banner, or a
                // "Check in at <place>" quick action
                NotificationCenter.default.post(name: .navigateToCheckIn, object: id)
            case .quickCheckIn:
                // The static "Check In" quick action: no place, the sheet's picker takes over
                NotificationCenter.default.post(name: .navigateToCheckIn, object: nil)
            }
        }
    }

    /// Cold-launch navigation: the pending-open place can only be pushed once
    /// the tab bar is the root. Poll briefly; if the UI never settles, stash
    /// the standard pendingDeepLink so the next launch lands it.
    func navigateToCircleWhenReady(_ circleId: String, attempts: Int) {
        if window?.rootViewController is CirclesTabBarController {
            navigateToCircle(circleId: circleId)
            return
        }
        guard attempts > 0 else {
            UserDefaults.standard.set("circle:\(circleId)", forKey: "pendingDeepLink")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.navigateToCircleWhenReady(circleId, attempts: attempts - 1)
        }
    }

    func navigateToPlaceWhenReady(_ placeId: String, attempts: Int) {
        if window?.rootViewController is CirclesTabBarController {
            navigateToPlace(placeId: placeId)
            return
        }
        guard attempts > 0 else {
            UserDefaults.standard.set("place:\(placeId)", forKey: "pendingDeepLink")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.navigateToPlaceWhenReady(placeId, attempts: attempts - 1)
        }
    }

    /// Paywall entry for the share extension's upgrade path — server-enforced
    /// place limit, .placeLimit copy.
    func presentUpgradePaywall() {
        guard AuthService.shared.isLoggedIn,
              let tabBarController = window?.rootViewController as? CirclesTabBarController else { return }
        let host = tabBarController.presentedViewController ?? tabBarController
        SubscriptionManager.shared.showPaywall(from: host, reason: .placeLimit)
    }

    // MARK: - Video Deep Link Handling

    private func handleVideoDeepLink(videoId: String) {
        Logger.debug("📱 SceneDelegate: handleVideoDeepLink called with videoId: \(videoId)")

        // If user is not logged in, store the video link and prompt login
        guard AuthService.shared.isLoggedIn else {
            Logger.debug("📱 SceneDelegate: User not logged in, storing pending video link")
            UserDefaults.standard.set("video:\(videoId)", forKey: "pendingDeepLink")

            // Show alert prompting user to login
            if let rootVC = window?.rootViewController {
                // Login: the auth state listener handles showing the login screen
                AlertPresenter.showConfirmation(
                    title: "Login Required",
                    message: "Please login to view this video",
                    confirmTitle: "Login",
                    from: rootVC
                ) {}
            }
            return
        }

        // Navigate to video
        navigateToVideo(videoId: videoId)
    }

    func navigateToVideo(videoId: String) {
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
                    // The server says why: "This moment has disappeared." for a
                    // disappearing moment that ran out, not connected, etc.
                    AlertPresenter.showError(
                        title: "Moment Unavailable",
                        message: error.serverMessage ?? "This moment is no longer available.",
                        from: navController)
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

    /// Engagement-tip deep link: show all of the user's places on the expanded
    /// map. The tab bar observer does the actual presentation; here we just hand
    /// off (or re-stash if the interface isn't up yet, e.g. pre-login).
    /// Push-tap helper: land on the Me tab (venue claims are managed there)
    func navigateToMeTab() {
        guard AuthService.shared.isLoggedIn,
              let tabBarController = window?.rootViewController as? CirclesTabBarController else { return }
        tabBarController.selectedIndex = 3
    }

    private func navigateToAllPlacesMap(focusCategory: String? = nil) {
        guard AuthService.shared.isLoggedIn,
              window?.rootViewController is CirclesTabBarController else {
            UserDefaults.standard.set("all-places-map", forKey: "pendingDeepLink")
            return
        }
        var userInfo: [AnyHashable: Any] = [:]
        if let focusCategory = focusCategory { userInfo["focus"] = focusCategory }
        NotificationCenter.default.post(name: .navigateToAllPlacesMap, object: nil, userInfo: userInfo)
    }

    /// Engagement-tip deep link: open the Piggy Bank wallet-create coach-mark.
    /// Home → Widgets segment → one widget's page (e.g. the postcard
    /// composer from the app icon's "Send a Postcard" quick action).
    func navigateToWidget(id: String, postcardOrderId: String? = nil, quoteId: String? = nil,
                                  workoutPostId: String? = nil, motivationLineId: String? = nil,
                                  motivationSend: Bool = false, postcardShareToken: String? = nil,
                                  eventToken: String? = nil, eventId: String? = nil,
                                  runId: String? = nil, runToken: String? = nil, careAskId: String? = nil,
                                  fridgeMailCardId: String? = nil, clubToken: String? = nil,
                                  clubId: String? = nil, clubPostId: String? = nil,
                                  dogPostId: String? = nil, dailyDogId: String? = nil) {
        guard AuthService.shared.isLoggedIn,
              let tabBar = window?.rootViewController as? CirclesTabBarController else {
            let motivation: String? = motivationSend ? motivationLineId.map { "motivation-send:\($0)" } : nil
            let share: String? = postcardShareToken.map { "postcard-share:\($0)" }
            // Split up: one long ?? chain is too much for the type checker
            var club: String? = clubToken.map { "club-token:\($0)" }
            if club == nil, let clubId {
                club = clubPostId.map { "club-id:\(clubId)/\($0)" } ?? "club-id:\(clubId)"
            }
            if club == nil {
                club = dogPostId.map { "dog-post:\($0)" } ?? dailyDogId.map { "daily-dog:\($0)" }
            }
            let widgetTarget: String? = careAskId.map { "care-ask:\($0)" }
                ?? fridgeMailCardId.map { "fridgemail-card:\($0)" }
                ?? club
            let event: String? = eventToken.map { "event:\($0)" } ?? eventId.map { "event-id:\($0)" }
                ?? runId.map { "run-id:\($0)" } ?? runToken.map { "run-token:\($0)" }
                ?? widgetTarget
            let pending: String = postcardOrderId.map { "postcard-order:\($0)" }
                ?? quoteId.map { "quote:\($0)" }
                ?? workoutPostId.map { "workout:\($0)" }
                ?? motivation
                ?? share
                ?? event
                ?? "widget:\(id)"
            UserDefaults.standard.set(pending, forKey: "pendingDeepLink")
            return
        }
        // A shared quote opens straight on the quote, over whatever is showing
        if id == "quotes", let quoteId, tabBar.presentQuoteReel(quoteId: quoteId) { return }
        tabBar.presentedViewController?.dismiss(animated: false)
        tabBar.selectedIndex = 0
        guard let nav = tabBar.viewControllers?.first as? UINavigationController,
              let home = nav.viewControllers.first as? CirclesHomeViewController else { return }
        nav.popToRootViewController(animated: false)
        home.showWidgetsTab(openingWidget: id, postcardOrderId: postcardOrderId, quoteId: quoteId, workoutPostId: workoutPostId,
                            motivationLineId: motivationLineId, motivationSend: motivationSend,
                            postcardShareToken: postcardShareToken, eventToken: eventToken, eventId: eventId,
                            runId: runId, runToken: runToken, careAskId: careAskId, fridgeMailCardId: fridgeMailCardId,
                            clubToken: clubToken, clubId: clubId, clubPostId: clubPostId,
                            dogPostId: dogPostId, dailyDogId: dailyDogId)
    }

    /// A shared tab link: Home → that segment. Stashed like a widget link
    /// when nobody is signed in or the tab bar isn't up yet, which is the
    /// usual case for a link someone was sent.
    private func navigateToHomeTab(_ segment: HomeContentSegment) {
        guard AuthService.shared.isLoggedIn,
              let tabBar = window?.rootViewController as? CirclesTabBarController else {
            if let slug = segment.shareSlug { UserDefaults.standard.set("tab:\(slug)", forKey: "pendingDeepLink") }
            return
        }
        tabBar.presentedViewController?.dismiss(animated: false)
        tabBar.selectedIndex = 0
        guard let nav = tabBar.viewControllers?.first as? UINavigationController,
              let home = nav.viewControllers.first as? CirclesHomeViewController else { return }
        nav.popToRootViewController(animated: false)
        home.showHomeTab(segment)
    }

    private func navigateToCreateWallet() {
        guard AuthService.shared.isLoggedIn,
              window?.rootViewController is CirclesTabBarController else {
            UserDefaults.standard.set("create-wallet", forKey: "pendingDeepLink")
            return
        }
        NotificationCenter.default.post(name: .navigateToCreateWallet, object: nil)
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

    /// A milestone push's screen: the celebration, and your month underneath
    func showMilestone(_ milestone: PushMilestone) {
        guard AuthService.shared.isLoggedIn, window?.rootViewController is CirclesTabBarController else {
            UserDefaults.standard.set(milestone.pendingLink, forKey: "pendingDeepLink")
            return
        }
        let screen = UINavigationController(rootViewController: MilestoneMonthViewController(milestone: milestone))
        topViewController()?.present(screen, animated: true)
    }
}
