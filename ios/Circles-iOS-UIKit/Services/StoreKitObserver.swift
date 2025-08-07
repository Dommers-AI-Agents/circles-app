import Foundation
import StoreKit

/// Handles promoted in-app purchases initiated from the App Store
@MainActor
class StoreKitObserver: NSObject, SKPaymentTransactionObserver {
    static let shared = StoreKitObserver()
    
    // Store deferred payment if user needs to log in first
    private var deferredPayment: SKPayment?
    private var deferredProduct: SKProduct?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Setup
    
    func startObserving() {
        print("💎 StoreKitObserver: Starting to observe payment queue")
        SKPaymentQueue.default().add(self)
    }
    
    func stopObserving() {
        print("💎 StoreKitObserver: Stopping payment queue observation")
        SKPaymentQueue.default().remove(self)
    }
    
    // MARK: - SKPaymentTransactionObserver
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        // This is handled by StoreKit 2 in SubscriptionService
        // We only need this observer for promoted purchases
        print("💎 StoreKitObserver: Updated transactions called (handled by StoreKit 2)")
    }
    
    /// Called when a user initiates an in-app purchase from the App Store
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        print("💎 ===== PROMOTED PURCHASE DETECTED =====")
        print("💎 Product ID: \(product.productIdentifier)")
        print("💎 Product Title: \(product.localizedTitle)")
        print("💎 Product Price: \(product.priceLocale.currencySymbol ?? "")\(product.price)")
        
        // Check if user is logged in
        guard AuthService.shared.isLoggedIn else {
            print("💎 User not logged in - deferring purchase")
            
            // Store the payment for later
            deferredPayment = payment
            deferredProduct = product
            
            // Post notification to prompt login
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("PromotedPurchaseRequiresLogin"),
                    object: nil,
                    userInfo: ["productId": product.productIdentifier]
                )
            }
            
            // Return false to defer the payment
            return false
        }
        
        // User is logged in - check if already subscribed
        let isSubscribed = SubscriptionManager.shared.isSubscribed
        
        if isSubscribed {
            print("💎 User already subscribed - showing subscription status")
            
            // Post notification to show current subscription
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("PromotedPurchaseAlreadySubscribed"),
                    object: nil
                )
            }
            
            // Don't process the payment
            return false
        }
        
        print("💎 User logged in and not subscribed - proceeding with purchase")
        
        // Post notification to handle the purchase through our UI
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("ProcessPromotedPurchase"),
                object: nil,
                userInfo: ["productId": product.productIdentifier]
            )
        }
        
        // Return false because we'll handle it through StoreKit 2
        // The notification will trigger our normal purchase flow
        return false
    }
    
    // MARK: - Deferred Purchase Handling
    
    /// Resume a deferred purchase after user logs in
    func resumeDeferredPurchase() {
        guard let payment = deferredPayment,
              let product = deferredProduct else {
            print("💎 No deferred purchase to resume")
            return
        }
        
        print("💎 Resuming deferred purchase for product: \(product.productIdentifier)")
        
        // Clear deferred purchase
        deferredPayment = nil
        deferredProduct = nil
        
        // Check if user is now logged in
        guard AuthService.shared.isLoggedIn else {
            print("💎 User still not logged in - cannot resume purchase")
            return
        }
        
        // Post notification to process the purchase
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("ProcessPromotedPurchase"),
                object: nil,
                userInfo: ["productId": product.productIdentifier]
            )
        }
    }
    
    /// Check if there's a deferred purchase waiting
    var hasDeferredPurchase: Bool {
        return deferredPayment != nil
    }
    
    /// Clear any deferred purchase
    func clearDeferredPurchase() {
        deferredPayment = nil
        deferredProduct = nil
        print("💎 Cleared deferred purchase")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a promoted purchase requires user login
    static let promotedPurchaseRequiresLogin = Notification.Name("PromotedPurchaseRequiresLogin")
    
    /// Posted when a promoted purchase is attempted but user is already subscribed
    static let promotedPurchaseAlreadySubscribed = Notification.Name("PromotedPurchaseAlreadySubscribed")
    
    /// Posted when a promoted purchase should be processed
    static let processPromotedPurchase = Notification.Name("ProcessPromotedPurchase")
}