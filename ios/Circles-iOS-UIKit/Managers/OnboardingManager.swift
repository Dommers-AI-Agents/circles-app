import Foundation
import UIKit

// MARK: - Helper Structs
struct EmptyBody: Codable {}

// MARK: - Tutorial Steps
//
// A 4-step HOME-PAGE tour (Wes, 2026-08-19) — every bubble points at a real
// control on the home screen and Next advances to the next one. The old
// cross-screen chain (welcome → create circle → add place → network →
// privacy) is gone; teaching happens where the user already is.
//
// Raw values are deliberately NEW ("tour_*", not the old "tutorial_*"):
// completedTutorialSteps persists raw strings in UserDefaults, and devices
// that ran the old tutorial hold the old strings — fresh values mean the new
// tour runs everywhere without depending on a reset.
enum TutorialStep: String, CaseIterable {
    case addPlaces = "tour_add_places"
    case followUsers = "tour_follow_users"
    case viewActivity = "tour_view_activity"
    // Was "See Your Rewards" (FavCoins 🌵) until 2026-10-09 — too much on
    // day one; the last step now shows the widgets instead
    case seeWidgets = "tour_see_widgets"
    // "Keep going" after the basics (Wes, 2026-11-01): the rest of the app
    case moments = "tour_moments"
    case locals = "tour_locals"
    case checkIn = "tour_check_in"
    case rewards = "tour_rewards"
    case profile = "tour_profile"

    /// The four everyone sees; the rest follow "Keep going"
    static let basics: [TutorialStep] = [.addPlaces, .followUsers, .viewActivity, .seeWidgets]
    var isBasic: Bool { Self.basics.contains(self) }

    /// "2 of 4" among the basics, "2 of 5" among the extras
    var progressText: String {
        let run = isBasic ? Self.basics : Self.allCases.filter { !$0.isBasic }
        let index = (run.firstIndex(of: self) ?? 0) + 1
        return "\(index) of \(run.count)"
    }

    var title: String {
        switch self {
        case .addPlaces:
            return "Build Your Map"
        case .followUsers:
            return "Explore Other People's Maps"
        case .viewActivity:
            return "See What's New"
        case .seeWidgets:
            return "Your Widgets"
        case .moments:
            return "Moments"
        case .locals:
            return "Locals"
        case .checkIn:
            return "Check In"
        case .rewards:
            return "FavCoins and Rewards"
        case .profile:
            return "Your Profile"
        }
    }

    var description: String {
        switch self {
        case .addPlaces:
            // Both ways in (Wes, 2026-10-17): one place, or the whole map from photos
            return "Tap Add Place to search for a spot you love, or choose Add from photos to build your map from the places in your photos. Your photos stay on your phone."
        case .followUsers:
            return "Tap a face to see their map. Follow people and their favorites show up on yours"
        case .viewActivity:
            return "What the people you follow are saving, checking into, and loving"
        case .seeWidgets:
            return "Weather, workouts, postcards, events and more — tap Widgets to scroll through them all"
        case .moments:
            return "Short videos and photos from the places your people love. Share your own from any place."
        case .locals:
            return "Specials, events and markets near you, from the stores and spots around town."
        case .checkIn:
            return "Tap the walking person when you're somewhere you love. Your check-ins build your history and earn rewards."
        case .rewards:
            return "Your FavCoins and the points you've earned at stores live here. Scan a store's code at the register to earn more."
        case .profile:
            return "Your map, circles and moments in one place. Share it so friends can follow you."
        }
    }
}

// MARK: - Onboarding Manager
class OnboardingManager {
    static let shared = OnboardingManager()

    /// True while SceneDelegate is driving the deterministic first-session
    /// chain (carousel → first-people sheet → notification onboarding →
    /// tutorial decision). Home-screen one-time prompts and the tutorial
    /// check defer to the chain while it's active instead of racing it.
    var isFirstSessionFlowActive = false
    
    // UserDefaults keys
    private let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    private let completedTutorialStepsKey = "completedTutorialSteps"
    private let tutorialStartDateKey = "tutorialStartDate"
    private let shouldShowTutorialKey = "shouldShowTutorial"
    private let hasShownContactsPermissionKey = "hasShownContactsPermission"
    private let shouldShowSuggestedUsersKey = "shouldShowSuggestedUsers"
    private let hasShownVisitTrackingPermissionKey = "hasShownVisitTrackingPermission"
    private let visitTrackingPermissionResponseKey = "visitTrackingPermissionResponse"
    private let hasShownAddPlaceTutorialKey = "hasShownAddPlaceTutorial"
    private let hasShownAddPlaceMapHintKey = "hasShownAddPlaceMapHint"
    private let hasShownConnectionAvatarHintKey = "hasShownConnectionAvatarHint"
    private let hasShownHomeWidgetsHintKey = "hasShownHomeWidgetsHint"
    
    // Current tutorial state
    private var completedSteps: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: completedTutorialStepsKey) ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: completedTutorialStepsKey)
        }
    }
    
    /// The bubble on screen (the home tour's or a ScreenGuide's: never two)
    var currentBubbleView: BubbleView?

    /// The screen "Show me" just opened explains itself (ScreenGuide)
    var pendingGuide: ScreenGuideKind?
    /// They're adding a place from a guide: when it's saved, open it with its guide
    private var awaitingOwnPlace = false
    private var placeAddedObserver: NSObjectProtocol?

    /// A guide is waiting on its screen, or on the place they're adding
    var isGuideInProgress: Bool { pendingGuide != nil || awaitingOwnPlace }

    /// Which guide a scanned "show me how" QR sent (Scan Actions,
    /// 2026-11-11): it runs whether or not the tour is done. Decided when its
    /// screen takes it, so one that never opened can't change a later tour
    /// guide.
    private var scanGuideKind: ScreenGuideKind?
    /// The guide on screen came from a scan: its last button ends it instead
    /// of going back to the tour
    private(set) var isScanGuide = false

    /// True once, for the screen the tour (or a scanned QR) sent them to
    func takeGuide(_ kind: ScreenGuideKind) -> Bool {
        let fromScan = scanGuideKind == kind
        guard pendingGuide == kind, shouldShowTutorial || fromScan else { return false }
        pendingGuide = nil
        scanGuideKind = nil
        isScanGuide = fromScan
        return true
    }

    /// A scanned guide QR: the screen it opens explains itself
    func sendScanGuide(_ kind: ScreenGuideKind) {
        dismissCurrentBubble()
        scanGuideKind = kind
        pendingGuide = kind
    }

    /// The scanned guide was finished or put away
    func endScanGuide() {
        isScanGuide = false
    }

    /// "Add a place you love" from a guide: Add Place explains itself, and
    /// the place they save opens with what they can do with it
    func startAddPlaceFromGuide() {
        isTourPaused = true
        pendingGuide = .addPlace
        awaitingOwnPlace = true
        if placeAddedObserver == nil {
            placeAddedObserver = NotificationCenter.default.addObserver(
                forName: .placeAddedToCircle, object: nil, queue: .main
            ) { [weak self] note in
                guard let self, self.awaitingOwnPlace, let place = note.userInfo?["place"] as? Place else { return }
                self.awaitingOwnPlace = false
                self.pendingGuide = .ownPlace
                // After Add Place closes and the coin drop plays
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    NotificationCenter.default.post(name: .navigateToPlace, object: place.id)
                }
            }
        }
        NextStepNavigator.addPlace()
    }

    /// "Show me" or the video took them off Home mid-tour: Home picks the
    /// tour up again when it's back on screen (2026-11-01)
    var isTourPaused = false
    /// They chose "Keep going" after the basics this session
    var tourKeepGoing = false
    
    private init() {}
    
    /// Reset all onboarding flags for a new user
    func resetForNewUser() {
        UserDefaults.standard.removeObject(forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.removeObject(forKey: completedTutorialStepsKey)
        UserDefaults.standard.removeObject(forKey: tutorialStartDateKey)
        UserDefaults.standard.removeObject(forKey: shouldShowTutorialKey)
        UserDefaults.standard.removeObject(forKey: hasShownContactsPermissionKey)
        UserDefaults.standard.removeObject(forKey: shouldShowSuggestedUsersKey)
        UserDefaults.standard.removeObject(forKey: hasShownVisitTrackingPermissionKey)
        UserDefaults.standard.removeObject(forKey: visitTrackingPermissionResponseKey)
        UserDefaults.standard.removeObject(forKey: hasShownAddPlaceTutorialKey)
        UserDefaults.standard.removeObject(forKey: hasShownAddPlaceMapHintKey)
        UserDefaults.standard.removeObject(forKey: hasShownConnectionAvatarHintKey)
        // Ensure the flag returns to default state (true)
        shouldShowSuggestedUsers = true
        Logger.info("Onboarding state reset for new user")
    }
    
    // MARK: - Public Methods
    
    /// Check if onboarding has been completed
    var hasCompletedOnboarding: Bool {
        return UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
    }
    
    /// Check if tutorial should be shown (user is new or has reset)
    var shouldShowTutorial: Bool {
        get {
            // If explicitly set, use that value
            if UserDefaults.standard.object(forKey: shouldShowTutorialKey) != nil {
                return UserDefaults.standard.bool(forKey: shouldShowTutorialKey)
            }
            // Otherwise, show if onboarding not completed
            return !hasCompletedOnboarding
        }
        set {
            UserDefaults.standard.set(newValue, forKey: shouldShowTutorialKey)
        }
    }
    
    /// Start (or resume) the onboarding tutorial. Callers hit this on every
    /// launch where the backend says the tutorial isn't finished — it must NOT
    /// wipe local progress, or a mid-tutorial relaunch dumps the user back at
    /// Welcome and they never see the connect/privacy steps. Explicit wipes
    /// live in resetTutorial()/resetForNewUser().
    func startTutorial() {
        if completedSteps.isEmpty {
            UserDefaults.standard.set(Date(), forKey: tutorialStartDateKey)
        }

        // Mark tutorial as active
        shouldShowTutorial = true

        Logger.info("Onboarding tutorial started/resumed (\(completedSteps.count) steps already done)")
    }
    
    /// Complete the entire onboarding
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: hasCompletedOnboardingKey)
        shouldShowTutorial = false
        dismissCurrentBubble()
        
        // Mark tutorial as completed on backend
        markTutorialCompleted()
        
        Logger.info("Onboarding completed")
    }
    
    /// Reset tutorial (for testing or user request)
    func resetTutorial() {
        UserDefaults.standard.removeObject(forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.removeObject(forKey: completedTutorialStepsKey)
        UserDefaults.standard.removeObject(forKey: tutorialStartDateKey)
        shouldShowTutorial = true
        Logger.info("Onboarding tutorial reset")
    }
    
    /// A home-tour bubble is on screen: nothing else should cover it (the
    /// daily card checks this). Deliberately not `shouldShowTutorial`, which
    /// stays true for anyone who never finished the tour.
    var isHomeTourInProgress: Bool { currentBubbleView != nil }

    /// Check if a specific step has been completed
    func hasCompletedStep(_ step: TutorialStep) -> Bool {
        return completedSteps.contains(step.rawValue)
    }
    
    /// Back: the previous step shows again
    func uncompleteStep(_ step: TutorialStep) {
        completedSteps.remove(step.rawValue)
    }

    /// Mark a step as completed
    func completeStep(_ step: TutorialStep) {
        completedSteps.insert(step.rawValue)
        
        // Check if all steps are completed
        if completedSteps.count >= TutorialStep.allCases.count {
            completeOnboarding()
        }
    }
    
    /// Show tutorial bubble for a specific step. `onAdvance` runs after Next
    /// completes the step — the home tour passes `{ runHomeTour() }` so each
    /// dismissal chains straight into the next bubble.
    func showTutorialStep(_ step: TutorialStep, targetView: UIView? = nil, in viewController: UIViewController, arrowDirection: BubbleView.ArrowDirection = .bottom, onAdvance: (() -> Void)? = nil,
                          onBack: (() -> Void)? = nil, onLearnMore: (() -> Void)? = nil, onVideo: (() -> Void)? = nil) {
        // Don't show if tutorial is not active or step already completed
        guard shouldShowTutorial, !hasCompletedStep(step) else { return }

        // Dismiss any existing bubble
        dismissCurrentBubble()

        // Create new bubble
        let bubble = BubbleView()
        let isLast = step == TutorialStep.allCases.last
        bubble.configureTour(title: step.title, description: step.description, arrowDirection: arrowDirection,
                             stepText: step.progressText, canGoBack: onBack != nil,
                             learnMore: onLearnMore != nil, video: onVideo != nil,
                             skipTitle: step.isBasic ? "Skip" : "Done", nextTitle: isLast ? "Done" : "Next")
        // Every bubble and button reaches the server (TourTelemetry), so a
        // new person's tour leaves a trace of where they stopped
        let report = { (action: TourTelemetry.Action) in NextStepService.shared.recordTour(step: step.rawValue, action: action) }
        bubble.onBack = { [weak self] in
            report(.back)
            self?.dismissCurrentBubble()
            onBack?()
        }
        bubble.onLearnMore = { [weak self] in
            report(.learnMore)
            // Done with this step; the tour resumes when Home is back
            self?.completeStep(step)
            self?.isTourPaused = true
            self?.dismissCurrentBubble()
            onLearnMore?()
        }
        bubble.onVideo = { [weak self] in
            report(.video)
            self?.isTourPaused = true
            self?.dismissCurrentBubble()
            onVideo?()
        }

        // Set up actions
        bubble.onNext = { [weak self] in
            report(isLast ? .done : .next)
            self?.completeStep(step)
            self?.dismissCurrentBubble()
            onAdvance?()
        }

        bubble.onSkip = { [weak self] in
            report(step.isBasic ? .skip : .done)
            self?.completeOnboarding()
        }

        // Add to view hierarchy
        viewController.view.addSubview(bubble)
        bubble.pointTo(targetView, in: viewController.view)

        // Animate in
        bubble.show()
        report(.shown)

        // Store reference
        currentBubbleView = bubble
    }
    
    /// After the basics: "That's the basics. Keep going?" with the video
    func showKeepGoingCard(in viewController: UIViewController, onKeepGoing: @escaping () -> Void, onVideo: @escaping () -> Void) {
        guard shouldShowTutorial else { return }
        dismissCurrentBubble()
        let bubble = BubbleView()
        bubble.configureTour(title: "That\u{2019}s the basics",
                             description: "Want a quick look at Moments, Locals, check-ins, FavCoins and your profile?",
                             arrowDirection: .bottom, stepText: nil, canGoBack: false, learnMore: false, video: true,
                             skipTitle: "Done", nextTitle: "Keep going")
        let report = { (action: TourTelemetry.Action) in NextStepService.shared.recordTour(step: TourTelemetry.keepGoingStep, action: action) }
        bubble.onNext = { [weak self] in
            report(.keepGoing)
            self?.tourKeepGoing = true
            self?.dismissCurrentBubble()
            onKeepGoing()
        }
        bubble.onSkip = { [weak self] in
            report(.done)
            self?.completeOnboarding()
        }
        bubble.onVideo = { [weak self] in
            report(.video)
            self?.isTourPaused = true
            self?.dismissCurrentBubble()
            onVideo()
        }
        viewController.view.addSubview(bubble)
        bubble.pointTo(nil, in: viewController.view)
        bubble.show()
        report(.shown)
        currentBubbleView = bubble
    }

    /// Dismiss current bubble if any
    func dismissCurrentBubble() {
        currentBubbleView?.dismiss { [weak self] in
            self?.currentBubbleView?.removeFromSuperview()
            self?.currentBubbleView = nil
        }
    }
    
    // MARK: - New User Detection
    
    /// Check if user needs tutorial from backend
    /// Callers waiting on the one status request in flight: launch asked
    /// twice at once (SceneDelegate and Home, 2026-11-03)
    private var tutorialStatusWaiters: [(Bool) -> Void] = []

    func checkIfUserNeedsTutorial(completion: @escaping (Bool) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.checkIfUserNeedsTutorial(completion: completion) }
            return
        }
        let alreadyAsking = !tutorialStatusWaiters.isEmpty
        tutorialStatusWaiters.append(completion)
        guard !alreadyAsking else { return }
        fetchTutorialStatus { [weak self] needsTutorial in
            // The waiters list lives on the main queue
            DispatchQueue.main.async {
                guard let self else { return }
                let waiters = self.tutorialStatusWaiters
                self.tutorialStatusWaiters = []
                waiters.forEach { $0(needsTutorial) }
            }
        }
    }

    private func fetchTutorialStatus(completion: @escaping (Bool) -> Void) {
        APIService.shared.request(
            endpoint: "users/me/tutorial-status",
            method: .get
        ) { (result: Result<TutorialStatusResponse, APIError>) in
            switch result {
            case .success(let response):
                // User needs tutorial if they haven't completed it
                let needsTutorial = !response.hasCompletedTutorial
                
                // Update local state based on backend. The server already
                // says done: just the local side, no write-back (it re-wrote
                // the same flag on every launch, 2026-11-03)
                if response.hasCompletedTutorial {
                    UserDefaults.standard.set(true, forKey: self.hasCompletedOnboardingKey)
                    self.shouldShowTutorial = false
                    self.dismissCurrentBubble()
                } else {
                    self.shouldShowTutorial = true
                }
                
                completion(needsTutorial)
                
            case .failure(let error):
                Logger.error("Failed to check tutorial status: \(error)")
                // On error, check local state
                completion(self.shouldShowTutorial && !self.hasCompletedOnboarding)
            }
        }
    }
    
    /// Mark tutorial as completed on backend with retry logic
    func markTutorialCompleted() {
        markTutorialCompleted(retryCount: 0)
    }
    
    private func markTutorialCompleted(retryCount: Int) {
        APIService.shared.request(
            endpoint: "users/me/complete-tutorial",
            method: .post,
            body: [:] // Empty dictionary for POST with no body
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                Logger.info("Tutorial marked as completed on backend")
            case .failure(let error):
                Logger.error("Failed to mark tutorial completed (attempt \(retryCount + 1)): \(error)")
                
                // Retry logic for specific error types
                if retryCount < 2 { // Max 3 attempts
                    var shouldRetry = false
                    var retryDelay: TimeInterval = 2.0 // Base delay of 2 seconds
                    
                    switch error {
                    case .noInternet:
                        shouldRetry = true
                        retryDelay = 5.0 // Longer delay for network issues
                    case .rateLimited:
                        shouldRetry = true
                        retryDelay = Double(retryCount + 1) * 3.0 // Exponential backoff
                    case .requestFailed, .serverError:
                        shouldRetry = true
                        retryDelay = Double(retryCount + 1) * 2.0 // Progressive delay
                    default:
                        shouldRetry = false // Don't retry for auth errors, etc.
                    }
                    
                    if shouldRetry {
                        Logger.warning("Retrying tutorial completion in \(Int(retryDelay)) seconds...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                            self.markTutorialCompleted(retryCount: retryCount + 1)
                        }
                    } else {
                        Logger.error("Not retrying tutorial completion due to error type: \(error)")
                    }
                } else {
                    Logger.error("Max retry attempts exceeded for tutorial completion")
                }
            }
        }
    }
    
    // MARK: - Add Place Tutorial
    
    /// Check if user should see add place tutorial
    func shouldShowAddPlaceTutorial() -> Bool {
        // Show if user hasn't seen it before
        return !UserDefaults.standard.bool(forKey: hasShownAddPlaceTutorialKey)
    }
    
    func markAddPlaceTutorialShown() {
        UserDefaults.standard.set(true, forKey: hasShownAddPlaceTutorialKey)
        Logger.info("Add place tutorial marked as shown")
    }

    /// Check if user should see the "tap the map or search" hint bubble in the Add Place view
    func shouldShowAddPlaceMapHint() -> Bool {
        return !UserDefaults.standard.bool(forKey: hasShownAddPlaceMapHintKey)
    }

    func markAddPlaceMapHintShown() {
        UserDefaults.standard.set(true, forKey: hasShownAddPlaceMapHintKey)
        Logger.info("Add place map hint marked as shown")
    }

    /// Check if user should see the one-time hint bubble on the home Widgets tab
    // MARK: - Rewards hint (2026-10-29)

    /// Armed the first time a store code earns points; Home then points at
    /// its $ button once: "all your reward points live here".
    static let rewardsHintArmed = Notification.Name.rewardsHintArmed
    private let rewardsHintArmedKey = "rewardsHintArmed"
    private let rewardsHintShownKey = "rewardsHintShown"

    func armRewardsHint() {
        guard !UserDefaults.standard.bool(forKey: rewardsHintShownKey) else { return }
        UserDefaults.standard.set(true, forKey: rewardsHintArmedKey)
        NotificationCenter.default.post(name: Self.rewardsHintArmed, object: nil)
    }

    func shouldShowRewardsHint() -> Bool {
        UserDefaults.standard.bool(forKey: rewardsHintArmedKey) && !UserDefaults.standard.bool(forKey: rewardsHintShownKey)
    }

    func markRewardsHintShown() {
        UserDefaults.standard.set(true, forKey: rewardsHintShownKey)
        UserDefaults.standard.set(false, forKey: rewardsHintArmedKey)
    }

    func shouldShowHomeWidgetsHint() -> Bool {
        return !UserDefaults.standard.bool(forKey: hasShownHomeWidgetsHintKey)
    }

    func markHomeWidgetsHintShown() {
        UserDefaults.standard.set(true, forKey: hasShownHomeWidgetsHintKey)
        Logger.info("Home widgets hint marked as shown")
    }

    /// Re-arm the one-time Add Place hints so a replayed welcome tour shows them again
    func resetAddPlaceHints() {
        UserDefaults.standard.removeObject(forKey: hasShownAddPlaceTutorialKey)
        UserDefaults.standard.removeObject(forKey: hasShownAddPlaceMapHintKey)
    }

    /// Check if user should see the tap/long-press hint bubble on the home
    /// screen's connection avatar row
    func shouldShowConnectionAvatarHint() -> Bool {
        return !UserDefaults.standard.bool(forKey: hasShownConnectionAvatarHintKey)
    }

    func markConnectionAvatarHintShown() {
        UserDefaults.standard.set(true, forKey: hasShownConnectionAvatarHintKey)
        Logger.info("Connection avatar hint marked as shown")
    }
    
    // MARK: - Contacts Onboarding
    
    /// Check if contacts permission has been shown
    var hasShownContactsPermission: Bool {
        get {
            return UserDefaults.standard.bool(forKey: hasShownContactsPermissionKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasShownContactsPermissionKey)
        }
    }
    
    /// Check if suggested users should be shown
    var shouldShowSuggestedUsers: Bool {
        get {
            // Show if not explicitly set to false
            if UserDefaults.standard.object(forKey: shouldShowSuggestedUsersKey) != nil {
                return UserDefaults.standard.bool(forKey: shouldShowSuggestedUsersKey)
            }
            return true // Default to true for new users
        }
        set {
            UserDefaults.standard.set(newValue, forKey: shouldShowSuggestedUsersKey)
        }
    }
    
    /// Check if user needs contacts onboarding
    func shouldShowContactsOnboarding() -> Bool {
        // Show contacts permission if:
        // 1. User is new (hasn't completed onboarding)
        // 2. Haven't shown contacts permission before
        return !hasCompletedOnboarding && !hasShownContactsPermission
    }
    
    /// Mark contacts permission as shown
    func markContactsPermissionShown() {
        hasShownContactsPermission = true
    }
    
    /// Check if user should see suggested users overlay
    func shouldShowSuggestedUsersOverlay(connectionCount: Int) -> Bool {
        // Show suggested users if:
        // 1. User has 0 connections
        // 2. Feature is enabled (not explicitly disabled)
        // Always show for users with 0 connections, regardless of tutorial or onboarding status
        
        // If user has 0 connections and we haven't checked yet this session,
        // enable the overlay to ensure they see it
        if connectionCount == 0 && !hasCheckedSuggestedUsersThisSession {
            hasCheckedSuggestedUsersThisSession = true
            shouldShowSuggestedUsers = true
            Logger.info("Auto-enabled suggested users overlay for user with 0 connections")
        }
        
        return connectionCount == 0 && shouldShowSuggestedUsers
    }
    
    // Track if we've checked this session to avoid overriding user's choice
    private var hasCheckedSuggestedUsersThisSession = false
    
    /// Disable suggested users overlay
    func disableSuggestedUsersOverlay() {
        shouldShowSuggestedUsers = false
    }
    
    /// Enable suggested users overlay (for testing or resetting)
    func enableSuggestedUsersOverlay() {
        shouldShowSuggestedUsers = true
    }
    
    // MARK: - Visit Tracking Permission
    
    /// Check if visit tracking permission has been shown
    var hasShownVisitTrackingPermission: Bool {
        get {
            return UserDefaults.standard.bool(forKey: hasShownVisitTrackingPermissionKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasShownVisitTrackingPermissionKey)
        }
    }
    
    /// Get the user's response to visit tracking permission
    var visitTrackingPermissionResponse: Bool? {
        get {
            if UserDefaults.standard.object(forKey: visitTrackingPermissionResponseKey) != nil {
                return UserDefaults.standard.bool(forKey: visitTrackingPermissionResponseKey)
            }
            return nil
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: visitTrackingPermissionResponseKey)
            } else {
                UserDefaults.standard.removeObject(forKey: visitTrackingPermissionResponseKey)
            }
        }
    }
    
    /// Check if user should see visit tracking permission
    func shouldShowVisitTrackingPermission() -> Bool {
        // Show if not shown before and user has completed suggested users
        return !hasShownVisitTrackingPermission && !hasCompletedOnboarding
    }
    
    /// Mark visit tracking permission as shown
    func markVisitTrackingPermissionShown() {
        hasShownVisitTrackingPermission = true
    }
    
    /// Set the user's visit tracking permission response
    func setVisitTrackingPermissionResponse(enabled: Bool) {
        visitTrackingPermissionResponse = enabled
        markVisitTrackingPermissionShown()
    }
}