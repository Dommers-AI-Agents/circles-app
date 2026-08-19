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
    case seeRewards = "tour_see_rewards"

    var title: String {
        switch self {
        case .addPlaces:
            return "Add Your Favorite Places"
        case .followUsers:
            return "Follow New Users"
        case .viewActivity:
            return "View Recent Activity"
        case .seeRewards:
            return "See Your Rewards"
        }
    }

    var description: String {
        switch self {
        case .addPlaces:
            return "Tap Add Place to save any spot you love — it lands on your map"
        case .followUsers:
            return "Tap a face to see their places; suggested people are one tap away"
        case .viewActivity:
            return "See what your people are saving, checking into, and loving"
        case .seeRewards:
            return "Adding places and connecting earns FavCoins 🌵 — check your piggy bank here"
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
    
    private var currentBubbleView: BubbleView?
    
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
    
    /// Check if a specific step has been completed
    func hasCompletedStep(_ step: TutorialStep) -> Bool {
        return completedSteps.contains(step.rawValue)
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
    func showTutorialStep(_ step: TutorialStep, targetView: UIView? = nil, in viewController: UIViewController, arrowDirection: BubbleView.ArrowDirection = .bottom, onAdvance: (() -> Void)? = nil) {
        // Don't show if tutorial is not active or step already completed
        guard shouldShowTutorial, !hasCompletedStep(step) else { return }

        // Dismiss any existing bubble
        dismissCurrentBubble()

        // Create new bubble
        let bubble = BubbleView()
        bubble.configure(
            title: step.title,
            description: step.description,
            arrowDirection: arrowDirection
        )

        // Set up actions
        bubble.onNext = { [weak self] in
            self?.completeStep(step)
            self?.dismissCurrentBubble()
            onAdvance?()
        }

        bubble.onSkip = { [weak self] in
            self?.completeOnboarding()
        }

        // Add to view hierarchy
        viewController.view.addSubview(bubble)
        bubble.pointTo(targetView, in: viewController.view)

        // Animate in
        bubble.show()

        // Store reference
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
    func checkIfUserNeedsTutorial(completion: @escaping (Bool) -> Void) {
        APIService.shared.request(
            endpoint: "users/me/tutorial-status",
            method: .get
        ) { (result: Result<TutorialStatusResponse, APIError>) in
            switch result {
            case .success(let response):
                // User needs tutorial if they haven't completed it
                let needsTutorial = !response.hasCompletedTutorial
                
                // Update local state based on backend
                if response.hasCompletedTutorial {
                    self.completeOnboarding()
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