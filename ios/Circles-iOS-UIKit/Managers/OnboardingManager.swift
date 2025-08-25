import Foundation
import UIKit

// MARK: - Helper Structs
struct EmptyBody: Codable {}

// MARK: - Tutorial Steps
enum TutorialStep: String, CaseIterable {
    case welcome = "tutorial_welcome"
    case createCircle = "tutorial_create_circle"
    case addPlace = "tutorial_add_place"
    case exploreNetwork = "tutorial_explore_network"
    case privacySettings = "tutorial_privacy_settings"
    
    var title: String {
        switch self {
        case .welcome:
            return "Welcome to Circles!"
        case .createCircle:
            return "Create Your First Circle"
        case .addPlace:
            return "Add Places"
        case .exploreNetwork:
            return "Connect with Others"
        case .privacySettings:
            return "Privacy Controls"
        }
    }
    
    var description: String {
        switch self {
        case .welcome:
            return "Start building your collection of favorite places. Tap the + button to create your first circle"
        case .createCircle:
            return "Give your circle a unique name like 'Best Coffee Shops' or 'Date Night Spots' and choose a category"
        case .addPlace:
            return "Add your favorite places to any circle. Search for a place or browse nearby locations"
        case .exploreNetwork:
            return "Connect with friends to discover their favorite places and share yours"
        case .privacySettings:
            return "Control who can see your circles - keep them private, share with connections, or make them public"
        }
    }
}

// MARK: - Onboarding Manager
class OnboardingManager {
    static let shared = OnboardingManager()
    
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
    
    /// Start the onboarding tutorial
    func startTutorial() {
        // Reset completed steps
        completedSteps.removeAll()
        
        // Set tutorial start date
        UserDefaults.standard.set(Date(), forKey: tutorialStartDateKey)
        
        // Mark tutorial as active
        shouldShowTutorial = true
        
        Logger.info("Onboarding tutorial started")
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
    
    /// Show tutorial bubble for a specific step
    func showTutorialStep(_ step: TutorialStep, targetView: UIView? = nil, in viewController: UIViewController, arrowDirection: BubbleView.ArrowDirection = .bottom) {
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
            self?.handleNextStep(after: step, from: viewController)
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
    
    // MARK: - Private Methods
    
    private func handleNextStep(after step: TutorialStep, from viewController: UIViewController) {
        // Handle navigation to next tutorial step if needed
        switch step {
        case .welcome:
            // After welcome, the user can use the Add Place button
            // No specific action needed here
            break
            
        case .createCircle:
            // After creating circle, guide user to add places
            // The AddPlaceViewController will show the next tutorial step when it appears
            // Just dismiss the current view to let the user proceed
            if let navController = viewController.navigationController {
                navController.dismiss(animated: true) {
                    // The add place tutorial will be shown when AddPlaceViewController appears
                }
            }
            
        case .addPlace:
            // After adding place, navigate to network tab to show connections
            if let tabBar = viewController.tabBarController {
                // Switch to Network tab (index 3)
                tabBar.selectedIndex = 3
                
                // Show network tutorial after tab switch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let networkNav = tabBar.selectedViewController as? UINavigationController,
                       let myNetworkVC = networkNav.viewControllers.first as? MyNetworkViewController {
                        // The MyNetworkViewController will show its tutorial in viewDidAppear
                        // Just ensure the step is not marked as completed
                    }
                }
            }
            
        case .exploreNetwork:
            // After network exploration, show privacy settings in profile
            if let tabBar = viewController.tabBarController {
                // Switch to Profile tab (index 4)
                tabBar.selectedIndex = 4
                
                // Show privacy tutorial after tab switch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    if let profileNav = tabBar.selectedViewController as? UINavigationController,
                       let profileVC = profileNav.viewControllers.first as? ProfileViewController {
                        // Show privacy settings tutorial pointing to settings button
                        self?.showTutorialStep(
                            .privacySettings,
                            targetView: nil, // Will be centered
                            in: profileVC,
                            arrowDirection: .bottom
                        )
                    }
                }
            }
            
        case .privacySettings:
            // Tutorial complete!
            completeOnboarding()
            
            // Show a success message
            if let window = UIApplication.shared.windows.first,
               let rootVC = window.rootViewController {
                let alert = UIAlertController(
                    title: "Welcome to Circles! 🎉",
                    message: "You're all set! Start exploring and sharing your favorite places.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Let's Go!", style: .default))
                
                // Present from the topmost view controller
                var topVC = rootVC
                while let presented = topVC.presentedViewController {
                    topVC = presented
                }
                topVC.present(alert, animated: true)
            }
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