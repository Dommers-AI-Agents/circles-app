import Foundation
import StoreKit

class SubscriptionManager {
    static let shared = SubscriptionManager()
    
    private let service = SubscriptionService.shared
    private let userDefaults = UserDefaults.standard
    
    // UserDefaults keys
    private let kSubscriptionStatus = "subscription_status"
    private let kSubscriptionExpiryDate = "subscription_expiry_date"
    private let kTrialStartDate = "trial_start_date"
    private let kTrialEndDate = "trial_end_date"
    private let kHasSeenPaywall = "has_seen_paywall"
    private let kPaywallDismissedDate = "paywall_dismissed_date"
    
    private init() {
        setupPromotedPurchaseHandlers()
    }
    
    // MARK: - Initialization
    
    func initialize() async {
        // Load products
        do {
            try await service.loadProducts()
            await service.updateSubscriptionStatus()
        } catch {
            print("❌ Failed to initialize subscription service: \(error)")
        }
    }
    
    // MARK: - Status Checks
    
    @MainActor
    var isSubscribed: Bool {
        service.subscriptionStatus.isActive
    }
    
    @MainActor
    var subscriptionStatus: SubscriptionStatus {
        service.subscriptionStatus
    }
    
    @MainActor
    var subscriptionInfo: SubscriptionInfo? {
        service.subscriptionInfo
    }
    
    @MainActor
    var monthlyProduct: SubscriptionProduct? {
        service.products.first { $0.id == SubscriptionProduct.monthlyProductId }
    }
    
    // MARK: - Feature Access
    
    @MainActor
    func checkCircleLimit(currentCount: Int, from viewController: UIViewController) -> Bool {
        if service.canCreateMoreCircles(currentCount: currentCount) {
            return true
        }
        
        showPaywall(from: viewController, reason: .circleLimit)
        return false
    }
    
    @MainActor
    func checkPlaceLimit(currentCount: Int, from viewController: UIViewController) -> Bool {
        if service.canAddMorePlaces(currentCount: currentCount) {
            return true
        }
        
        showPaywall(from: viewController, reason: .placeLimit)
        return false
    }
    
    @MainActor
    func checkExportAccess(from viewController: UIViewController) -> Bool {
        if service.canExportContent() {
            return true
        }
        
        showPaywall(from: viewController, reason: .exportFeature)
        return false
    }
    
    // MARK: - Purchase Flow
    
    @MainActor
    func purchaseSubscription(from viewController: UIViewController) async throws {
        guard let product = monthlyProduct else {
            throw SubscriptionError.productNotFound
        }
        
        let transaction = try await service.purchase(product)
        
        if transaction != nil {
            // Show success
            AlertPresenter.showSuccess("Welcome to Circles Premium! 🎉", from: viewController)
        }
    }
    
    @MainActor
    func restorePurchases(from viewController: UIViewController) async {
        do {
            try await service.restorePurchases()
            
            if self.isSubscribed {
                AlertPresenter.showSuccess("Subscription restored successfully!", from: viewController)
            } else {
                AlertPresenter.showError(
                    title: "No Subscription Found",
                    message: "No active subscription found. Would you like to start a free trial?",
                    from: viewController
                )
            }
        } catch {
            AlertPresenter.showError(error, from: viewController)
        }
    }
    
    // MARK: - Paywall Management
    
    enum PaywallReason {
        case circleLimit
        case placeLimit
        case exportFeature
        case generalUpgrade
        
        var title: String {
            switch self {
            case .circleLimit:
                return "Circle Limit Reached"
            case .placeLimit:
                return "Place Limit Reached"
            case .exportFeature:
                return "Premium Feature"
            case .generalUpgrade:
                return "Upgrade to Premium"
            }
        }
        
        var message: String {
            switch self {
            case .circleLimit:
                return "Free users can create up to \(PremiumFeatures.maxFreeCircles) circles. Upgrade to Premium for unlimited circles!"
            case .placeLimit:
                return "Free users can add up to \(PremiumFeatures.maxFreePlacesPerCircle) places per circle. Upgrade to Premium for unlimited places!"
            case .exportFeature:
                return "Export and advanced sharing features are available to Premium members."
            case .generalUpgrade:
                return "Unlock all features with Circles Premium!"
            }
        }
    }
    
    @MainActor
    func showPaywall(from viewController: UIViewController, reason: PaywallReason) {
        let paywallVC = PaywallViewController(reason: reason)
        let navController = UINavigationController(rootViewController: paywallVC)
        navController.modalPresentationStyle = .pageSheet
        
        if let sheet = navController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        
        viewController.present(navController, animated: true)
        
        // Track paywall view
        userDefaults.set(true, forKey: kHasSeenPaywall)
        userDefaults.set(Date(), forKey: kPaywallDismissedDate)
    }
    
    // MARK: - Trial Management
    
    @MainActor
    func startFreeTrial() async throws {
        guard let product = monthlyProduct else {
            throw SubscriptionError.productNotFound
        }
        
        // Purchase with free trial
        let transaction = try await service.purchase(product)
        
        if transaction != nil {
            // Record trial start
            userDefaults.set(Date(), forKey: kTrialStartDate)
            
            let trialEndDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())
            userDefaults.set(trialEndDate, forKey: kTrialEndDate)
        }
    }
    
    @MainActor
    var isInFreeTrial: Bool {
        guard subscriptionStatus == .trial,
              let trialEndDate = userDefaults.object(forKey: kTrialEndDate) as? Date else {
            return false
        }
        
        return Date() < trialEndDate
    }
    
    @MainActor
    var trialDaysRemaining: Int? {
        guard isInFreeTrial,
              let trialEndDate = userDefaults.object(forKey: kTrialEndDate) as? Date else {
            return nil
        }
        
        let days = Calendar.current.dateComponents([.day], from: Date(), to: trialEndDate).day ?? 0
        return max(0, days)
    }
    
    // MARK: - Local Storage
    
    func saveSubscriptionStatus(_ status: SubscriptionStatus, expiryDate: Date?) {
        userDefaults.set(status.rawValue, forKey: kSubscriptionStatus)
        userDefaults.set(expiryDate, forKey: kSubscriptionExpiryDate)
    }
    
    func loadCachedSubscriptionStatus() -> SubscriptionStatus {
        guard let statusString = userDefaults.string(forKey: kSubscriptionStatus),
              let status = SubscriptionStatus(rawValue: statusString) else {
            return .none
        }
        
        // Check if expired
        if let expiryDate = userDefaults.object(forKey: kSubscriptionExpiryDate) as? Date,
           Date() > expiryDate {
            return .expired
        }
        
        return status
    }
    
    // MARK: - Promoted Purchase Handling
    
    private func setupPromotedPurchaseHandlers() {
        // Handle login required for promoted purchase
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePromotedPurchaseRequiresLogin),
            name: .promotedPurchaseRequiresLogin,
            object: nil
        )
        
        // Handle already subscribed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePromotedPurchaseAlreadySubscribed),
            name: .promotedPurchaseAlreadySubscribed,
            object: nil
        )
        
        // Handle process promoted purchase
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProcessPromotedPurchase),
            name: .processPromotedPurchase,
            object: nil
        )
    }
    
    @objc private func handlePromotedPurchaseRequiresLogin(_ notification: Notification) {
        print("💎 Promoted purchase requires login")
        
        DispatchQueue.main.async {
            guard let topViewController = self.getTopViewController() else { return }
            
            AlertPresenter.showConfirmation(
                title: "Sign In Required",
                message: "Please sign in to subscribe to Circles Premium",
                confirmTitle: "Sign In",
                from: topViewController
            ) {
                // Post notification to show login screen
                NotificationCenter.default.post(name: Notification.Name("ShowLoginForPromotedPurchase"), object: nil)
            }
        }
    }
    
    @objc private func handlePromotedPurchaseAlreadySubscribed(_ notification: Notification) {
        print("💎 User already subscribed to premium")
        
        DispatchQueue.main.async {
            guard let topViewController = self.getTopViewController() else { return }
            
            AlertPresenter.showSuccess(
                "You're already a Circles Premium member! 🎉",
                from: topViewController
            )
            
            // Optionally navigate to subscription management
            if topViewController.presentedViewController == nil {
                let subscriptionVC = SubscriptionViewController()
                let navController = UINavigationController(rootViewController: subscriptionVC)
                topViewController.present(navController, animated: true)
            }
        }
    }
    
    @objc private func handleProcessPromotedPurchase(_ notification: Notification) {
        print("💎 Processing promoted purchase")
        
        guard let productId = notification.userInfo?["productId"] as? String else {
            print("❌ No product ID in notification")
            return
        }
        
        DispatchQueue.main.async {
            guard let topViewController = self.getTopViewController() else { return }
            
            // Show paywall with promoted purchase context
            let paywallVC = PaywallViewController(reason: .generalUpgrade, promotedProductId: productId)
            let navController = UINavigationController(rootViewController: paywallVC)
            navController.modalPresentationStyle = .pageSheet
            
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
            
            topViewController.present(navController, animated: true)
        }
    }
    
    private func getTopViewController() -> UIViewController? {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           var topController = window.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            return topController
        }
        return nil
    }
}