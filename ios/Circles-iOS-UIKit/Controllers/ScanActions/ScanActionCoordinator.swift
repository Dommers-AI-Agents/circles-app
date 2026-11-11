import UIKit

/// A screen a "show me how" QR can open that explains itself
/// (ScreenGuideKind). It runs its guide on appear and when the coordinator
/// finds it already on screen; `OnboardingManager.takeGuide` makes it once.
protocol ScanGuideHost: UIViewController {
    func runScanGuideIfSent()
}

/// Runs a scanned Scan Action QR (2026-11-11): asks the server what the code
/// does (ScanActionPlan) and does it with the app's own screens: the place
/// cards and a circle to save into, a guide over the real screens, or a
/// store owner's claim and setup. Links that arrive before the app is ready
/// wait as "scan:<code>" (PendingLinkParser).
final class ScanActionCoordinator {
    static let shared = ScanActionCoordinator()

    private var inFlight: String?
    /// The same code twice in a moment (the clip's handoff and the URL iOS
    /// replays on the app's first launch) runs once
    private var lastStarted: (code: String, at: Date)?

    private var tabBar: CirclesTabBarController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController as? CirclesTabBarController }
            .first
    }

    /// The top of whatever is showing: where sheets and alerts go
    private var presenter: UIViewController? {
        var top: UIViewController? = tabBar
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    // MARK: - Starting

    func start(code raw: String) {
        guard let code = ScanActionLink.code(raw) else { return }
        guard AuthService.shared.isLoggedIn, tabBar != nil else {
            // Signed out or still launching: replayed after sign-in / onboarding
            UserDefaults.standard.set("scan:\(code)", forKey: "pendingDeepLink")
            return
        }
        // A brand-new account's first run (name, people, permissions) comes
        // first: the code waits for it, and survives a quit meanwhile
        if OnboardingManager.shared.isFirstSessionFlowActive {
            UserDefaults.standard.set("scan:\(code)", forKey: "pendingDeepLink")
            waitForFirstSession(code: code)
            return
        }
        if UserDefaults.standard.string(forKey: "pendingDeepLink") == "scan:\(code)" {
            UserDefaults.standard.removeObject(forKey: "pendingDeepLink")
        }
        guard inFlight != code else { return }
        if let last = lastStarted, last.code == code, Date().timeIntervalSince(last.at) < 20 { return }
        lastStarted = (code, Date())
        inFlight = code
        AnalyticsService.shared.logEvent("scan_action_opened", parameters: ["code_kind": code.count == 8 ? "made" : "guide"])
        let loading = presenter.map { AlertPresenter.showLoading(message: "Opening…", from: $0) }
        ScanActionService.shared.resolve(code: code) { [weak self] result in
            let go = {
                guard let self else { return }
                self.inFlight = nil
                switch result {
                case .success(let action):
                    self.perform(ScanActionPlan.plan(for: action), for: action)
                case .failure(let error):
                    guard let host = self.presenter else { return }
                    AlertPresenter.showError(message: (error as? ScanActionService.Refusal)?.message ?? FriendlyError.message(for: error), from: host)
                }
            }
            if let loading { loading.dismiss(animated: true, completion: go) } else { go() }
        }
    }

    private var waitingForFirstSession = false

    private func waitForFirstSession(code: String, attempts: Int = 0) {
        guard !waitingForFirstSession || attempts > 0 else { return }
        waitingForFirstSession = true
        // Up to ~15 minutes: picking a favorite place can take a while
        guard attempts < 450 else { waitingForFirstSession = false; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            if OnboardingManager.shared.isFirstSessionFlowActive {
                self.waitForFirstSession(code: code, attempts: attempts + 1)
            } else {
                self.waitingForFirstSession = false
                // A beat for the chain's last sheet to go
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.start(code: code) }
            }
        }
    }

    // MARK: - Doing it

    private func perform(_ plan: ScanActionPlan, for action: ScanAction) {
        guard let host = presenter else { return }
        AnalyticsService.shared.logEvent("scan_action_plan", parameters: ["kind": action.kind.rawValue])
        switch plan {
        case .review(let places, let preselected):
            presentReview(action: action, places: places, preselected: preselected, from: host)
        case .alreadyHaveAll(let places):
            if places.count == 1, let placeId = places[0].savedPlaceId {
                AlertPresenter.showInfo(title: "Already on your map", message: "You saved \(places[0].name) before.", from: host,
                                        actionTitle: "Open It") {
                    NotificationCenter.default.post(name: .navigateToPlace, object: placeId)
                }
            } else {
                AlertPresenter.showInfo(title: "Already on your map", message: "You already have all \(places.count) of these places.", from: host)
            }
        case .expired(let from):
            AlertPresenter.showInfo(title: "This QR has expired",
                                    message: from.map { "Ask \($0) to show you a new one." } ?? "Ask for a new one.", from: host)
        case .nothingLeft:
            AlertPresenter.showInfo(title: "Nothing to save", message: "The places in this QR aren't available anymore.", from: host)
        case .guide(let kind):
            runGuide(kind)
        case .claimStore:
            runGuide(.storeSetup)
        case .redeemStore(let name):
            confirmRedeem(action: action, storeName: name, from: host)
        case .manageStore(let venueId):
            openManageStore(venueId: venueId, withGuide: true)
        case .storeTaken(let name):
            AlertPresenter.showInfo(title: "Already set up",
                                    message: "Someone has already used this code\(name.map { " for \($0)" } ?? ""). If that wasn't you, contact FavCircles.",
                                    from: host)
        case .updateApp:
            AlertPresenter.showInfo(title: "Update FavCircles", message: "This code needs the newest version of the app.", from: host,
                                    linkTitle: "Open the App Store", linkURL: ShareLinks.appStoreURL)
        }
    }

    // MARK: Places

    private func presentReview(action: ScanAction, places: [ScanAction.Place], preselected: Set<String>, from host: UIViewController) {
        CircleService.shared.fetchUserCircles { result in
            DispatchQueue.main.async {
                let circles = (try? result.get()) ?? []
                let review = ScanPlacesReviewViewController(action: action, places: places, preselected: preselected, circles: circles)
                let nav = UINavigationController(rootViewController: review)
                nav.modalPresentationStyle = .pageSheet
                if let sheet = nav.sheetPresentationController {
                    sheet.detents = places.count == 1 ? [.medium(), .large()] : [.large()]
                    sheet.prefersGrabberVisible = true
                }
                (self.presenter ?? host).present(nav, animated: true)
            }
        }
    }

    // MARK: Guides

    /// Opens the screen a guide is about; it explains itself
    func runGuide(_ kind: ScreenGuideKind) {
        let onboarding = OnboardingManager.shared
        guard let tabs = tabBar else { return }
        tabs.presentedViewController?.dismiss(animated: false)
        switch kind {
        case .addPlace:
            onboarding.sendScanGuide(.addPlace)
            NextStepNavigator.addPlace()
        case .checkIn:
            onboarding.sendScanGuide(.checkIn)
            NotificationCenter.default.post(name: .navigateToCheckIn, object: nil)
        case .rewards:
            onboarding.sendScanGuide(.rewards)
            NextStepNavigator.rewards()
        case .widgets:
            onboarding.sendScanGuide(.widgets)
            NextStepNavigator.widgets()
            nudgeVisibleHost(after: 0.8)
        case .makeCircle:
            onboarding.sendScanGuide(.makeCircle)
            tabs.selectedIndex = 3
            (tabs.selectedViewController as? UINavigationController)?.popToRootViewController(animated: false)
            nudgeVisibleHost(after: 0.6)
        case .sharePlace:
            openOwnPlaceForShareGuide()
        case .storeSetup:
            onboarding.sendScanGuide(.storeSetup)
            NextStepNavigator.push(ClaimBusinessViewController())
        case .storeManage, .findPeople, .profile, .ownPlace:
            break
        }
    }

    /// The guide's screen may already be showing (no appear to start it)
    private func nudgeVisibleHost(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let tabs = self?.tabBar else { return }
            let nav = tabs.selectedViewController as? UINavigationController
            var candidates: [UIViewController] = []
            if let top = nav?.topViewController {
                candidates.append(top)
                candidates.append(contentsOf: top.children)
            }
            candidates.compactMap { $0 as? ScanGuideHost }.first?.runScanGuideIfSent()
        }
    }

    /// "Share a place" runs on one of their own places
    private func openOwnPlaceForShareGuide() {
        PlaceService.shared.getMyPlacesForCheckIn { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let place = (try? result.get())?.first else {
                    // Nothing to share yet: start with a place
                    if let host = self.presenter {
                        AlertPresenter.showInfo(title: "First, a place", message: "Save a place you love, then you can share it.", from: host,
                                                actionTitle: "Add a Place") { self.runGuide(.addPlace) }
                    }
                    return
                }
                OnboardingManager.shared.sendScanGuide(.sharePlace)
                guard let nav = self.tabBar?.selectedViewController as? UINavigationController else { return }
                nav.pushViewController(PlaceDetailViewController(place: place), animated: true)
            }
        }
    }

    // MARK: Store setup

    private func confirmRedeem(action: ScanAction, storeName: String, from host: UIViewController) {
        AlertPresenter.showConfirmation(
            title: "Make \(storeName) yours?",
            message: "This code from FavCircles makes you the owner of \(storeName)\(action.store?.address.map { ", \($0)" } ?? ""). Next you'll set your points and a first reward.",
            confirmTitle: "It's My Store",
            cancelTitle: "Not Now",
            from: host
        ) { [weak self] in
            self?.redeem(code: action.code, storeName: storeName)
        }
    }

    private func redeem(code: String, storeName: String) {
        guard let host = presenter else { return }
        let loading = AlertPresenter.showLoading(message: "Setting up \(storeName)…", from: host)
        let name = AuthService.shared.currentUser?.displayName
        ScanActionService.shared.redeemStore(code: code, contactName: name, contactPhone: nil) { [weak self] result in
            loading.dismiss(animated: true) {
                guard let self else { return }
                switch result {
                case .success(let done):
                    AnalyticsService.shared.logEvent("scan_action_store_redeemed")
                    guard let venueId = done.venueId else { return }
                    self.openManageStore(venueId: venueId, withGuide: true)
                case .failure(let error):
                    guard let host = self.presenter else { return }
                    AlertPresenter.showError(message: (error as? ScanActionService.Refusal)?.message ?? FriendlyError.message(for: error), from: host)
                }
            }
        }
    }

    /// Me → Manage Store for the store, with its walkthrough
    func openManageStore(venueId: String, withGuide: Bool) {
        RewardsService.shared.getMyVenues { [weak self] result in
            DispatchQueue.main.async {
                guard let self, let tabs = self.tabBar else { return }
                guard let venue = (try? result.get())?.first(where: { $0.venueId == venueId }) else {
                    if let host = self.presenter {
                        AlertPresenter.showInfo(title: "Almost there", message: "Your store is being set up. Find it on your Me tab under Manage Store in a minute.", from: host)
                    }
                    return
                }
                if withGuide { OnboardingManager.shared.sendScanGuide(.storeManage) }
                tabs.presentedViewController?.dismiss(animated: false)
                tabs.selectedIndex = 3
                guard let nav = tabs.selectedViewController as? UINavigationController else { return }
                nav.popToRootViewController(animated: false)
                nav.pushViewController(VenueManageViewController(venue: venue), animated: true)
            }
        }
    }
}
