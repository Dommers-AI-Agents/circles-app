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
            return "We've created some starter circles for you! Tap the + button to create your own custom circle"
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
            // After welcome, highlight the create circle button
            if let homeVC = viewController as? CirclesHomeViewController {
                homeVC.highlightCreateCircleButton()
            }
            
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
            endpoint: "/users/me/tutorial-status",
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
    
    /// Mark tutorial as completed on backend
    func markTutorialCompleted() {
        APIService.shared.request(
            endpoint: "/users/me/complete-tutorial",
            method: .post,
            body: [:] // Empty dictionary for POST with no body
        ) { (result: Result<SimpleAPIResponse, APIError>) in
            switch result {
            case .success:
                Logger.info("Tutorial marked as completed on backend")
            case .failure(let error):
                Logger.error("Failed to mark tutorial completed: \(error)")
            }
        }
    }
}