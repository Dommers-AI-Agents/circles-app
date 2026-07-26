import Foundation
import StoreKit

@MainActor
class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()
    
    @Published private(set) var products: [SubscriptionProduct] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    @Published private(set) var subscriptionStatus: SubscriptionStatus = .none
    @Published private(set) var subscriptionInfo: SubscriptionInfo?
    // FavCircles Business (store-owner) entitlement — tracked separately from
    // consumer premium; never merged into subscriptionStatus
    @Published private(set) var isBusinessSubscriber = false

    private var productIds = [
        SubscriptionProduct.monthlyProductId,
        SubscriptionProduct.annualProductId,
        SubscriptionProduct.businessMonthlyProductId,
        SubscriptionProduct.businessAnnualProductId
    ]

    /// Consumer premium products only (what the consumer paywall shows)
    var consumerProducts: [SubscriptionProduct] {
        products.filter { !$0.isBusinessProduct }
    }

    /// FavCircles Business products only (what the owner paywall shows)
    var businessProducts: [SubscriptionProduct] {
        products.filter { $0.isBusinessProduct }
    }
    private var updates: Task<Void, Never>? = nil
    
    private init() {
        // Start listening for transaction updates
        updates = observeTransactionUpdates()
    }
    
    deinit {
        updates?.cancel()
    }
    
    // MARK: - Load Products
    
    func loadProducts() async throws {
        Logger.debug("🔍 [SubscriptionService] Starting to load products...")
        Logger.debug("🔍 Product IDs to request: \(productIds)")
        Logger.debug("🔍 Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        
        do {
            Logger.debug("📱 Requesting products from StoreKit...")
            let storeProducts = try await Product.products(for: productIds)
            
            Logger.debug("📦 Received \(storeProducts.count) products from StoreKit")
            
            for product in storeProducts {
                Logger.debug("  ✅ Product loaded:")
                Logger.debug("     - ID: \(product.id)")
                Logger.debug("     - Display Name: \(product.displayName)")
                Logger.debug("     - Display Price: \(product.displayPrice)")
                Logger.debug("     - Type: \(product.type.rawValue)")
                if let subscription = product.subscription {
                    Logger.debug("     - Period: \(subscription.subscriptionPeriod)")
                    Logger.debug("     - Period Unit: \(subscription.subscriptionPeriod.unit)")
                    Logger.debug("     - Period Value: \(subscription.subscriptionPeriod.value)")
                }
            }
            
            products = storeProducts
                .map { SubscriptionProduct(product: $0) }
                .sorted { $0.price < $1.price }
            
            Logger.debug("✅ Successfully loaded and sorted \(products.count) subscription products")
            
            if products.isEmpty {
                Logger.debug("⚠️ WARNING: No products loaded. Possible reasons:")
                Logger.debug("   1. Products not configured in App Store Connect")
                Logger.debug("   2. Bundle ID mismatch")
                Logger.debug("   3. Products still processing (can take up to 24 hours)")
                Logger.debug("   4. Not signed in with sandbox account (for testing)")
                Logger.debug("   5. Paid Applications agreement not active")
            }
        } catch {
            Logger.debug("❌ Failed to load products from StoreKit")
            Logger.debug("❌ Error type: \(type(of: error))")
            Logger.debug("❌ Error description: \(error.localizedDescription)")
            
            if let skError = error as? StoreKitError {
                Logger.debug("❌ StoreKit Error: \(skError)")
                switch skError {
                case .networkError(let urlError):
                    Logger.debug("   - Network error: \(urlError)")
                case .systemError(let nsError):
                    Logger.debug("   - System error: \(nsError)")
                case .userCancelled:
                    Logger.debug("   - User cancelled")
                default:
                    Logger.debug("   - Other StoreKit error")
                }
            } else if let nsError = error as NSError? {
                Logger.debug("❌ NSError details:")
                Logger.debug("   - Domain: \(nsError.domain)")
                Logger.debug("   - Code: \(nsError.code)")
                Logger.debug("   - User Info: \(nsError.userInfo)")
            }
            
            throw error
        }
    }
    
    // MARK: - Purchase Subscription
    
    func purchase(_ product: SubscriptionProduct) async throws -> Transaction? {
        do {
            let result = try await product.product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                
                // Update subscription status
                await updateSubscriptionStatus()
                
                // Finish the transaction
                await transaction.finish()
                
                // Sync with backend
                await syncSubscriptionWithBackend(transaction: transaction)
                
                return transaction
                
            case .userCancelled:
                Logger.debug("⚠️ User cancelled purchase")
                return nil
                
            case .pending:
                Logger.debug("⏳ Purchase pending")
                return nil
                
            @unknown default:
                Logger.debug("❓ Unknown purchase result")
                return nil
            }
        } catch {
            Logger.debug("❌ Purchase failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Restore Purchases

    func restorePurchases() async throws {
        try await AppStore.sync()
        await updateSubscriptionStatus()

        // Sync with backend after restore
        await syncCurrentSubscriptionWithBackend()
    }
    
    // MARK: - Check Subscription Status
    
    func updateSubscriptionStatus() async {
        // Skip updating subscription status if user is not logged in
        guard AuthService.shared.isLoggedIn else {
            Logger.debug("💎 Skipping subscription status update - user not logged in")
            subscriptionStatus = .none
            return
        }
        
        var highestStatus: Product.SubscriptionInfo.Status? = nil
        var highestProduct: Product? = nil
        var hasBusinessEntitlement = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            guard transaction.productType == .autoRenewable else {
                continue
            }

            // Business subscriptions are a separate entitlement — they must
            // never set the consumer premium status
            if SubscriptionProduct.isBusinessProductId(transaction.productID) {
                hasBusinessEntitlement = true
                purchasedProductIDs.insert(transaction.productID)
                continue
            }

            guard let product = products.first(where: { $0.id == transaction.productID })?.product else {
                continue
            }
            
            guard let subscriptionInfo = product.subscription,
                  let status = try? await subscriptionInfo.status.first else {
                continue
            }
            
            // Find the highest priority status
            if highestStatus == nil || status.state.rawValue > (highestStatus?.state.rawValue ?? 0) {
                highestStatus = status
                highestProduct = product
            }
        }
        
        if let status = highestStatus, let product = highestProduct {
            // Update local subscription status
            switch status.state {
            case .subscribed:
                subscriptionStatus = .active
            case .inBillingRetryPeriod, .inGracePeriod:
                subscriptionStatus = .active // Still treat as active during grace period
            case .expired:
                subscriptionStatus = .expired
            case .revoked:
                subscriptionStatus = .cancelled
            default:
                subscriptionStatus = .none
            }
            
            // Create subscription info
            let renewalInfo = try? await product.subscription?.status.first?.renewalInfo
            
            // Check if auto-renew is enabled
            var willAutoRenew = false
            if let renewalInfo = renewalInfo {
                switch renewalInfo {
                case .verified(let renewal):
                    willAutoRenew = renewal.willAutoRenew
                case .unverified:
                    willAutoRenew = false
                }
            }
            
            // For StoreKit 2, we need to calculate expiry date from transaction
            var expiryDate: Date? = nil
            if let latestTransaction = await Transaction.latest(for: product.id),
               case .verified(let transaction) = latestTransaction {
                expiryDate = transaction.expirationDate
            }
            
            subscriptionInfo = SubscriptionInfo(
                status: subscriptionStatus,
                expiryDate: expiryDate,
                trialStartDate: nil, // Will be fetched from backend
                trialEndDate: nil, // Will be fetched from backend
                autoRenewEnabled: willAutoRenew,
                productId: product.id
            )
            
            purchasedProductIDs.insert(product.id)
        } else {
            // Check if user is in free trial (from backend)
            await checkTrialStatus()
        }

        isBusinessSubscriber = hasBusinessEntitlement
    }
    
    // MARK: - Transaction Observation
    
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) {
            for await _ in Transaction.updates {
                await updateSubscriptionStatus()
            }
        }
    }
    
    // MARK: - Verification
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - Backend Sync
    
    private func syncSubscriptionWithBackend(transaction: Transaction) async {
        // Get receipt data
        guard let appStoreReceiptURL = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: appStoreReceiptURL.path) else {
            Logger.debug("❌ No receipt found")
            return
        }

        do {
            let receiptData = try Data(contentsOf: appStoreReceiptURL)
            let receiptString = receiptData.base64EncodedString()

            let body: [String: Any] = [
                "receipt": receiptString,
                "transactionId": transaction.id,
                "productId": transaction.productID,
                "originalTransactionId": transaction.originalID,
                "purchaseDate": ISO8601DateFormatter().string(from: transaction.purchaseDate),
                "expirationDate": transaction.expirationDate.map { ISO8601DateFormatter().string(from: $0) } ?? nil
            ]

            let isBusinessReceipt = SubscriptionProduct.isBusinessProductId(transaction.productID)
            APIService.shared.request(
                endpoint: "users/subscription/verify",
                method: .post,
                body: body,
                requiresAuth: true
            ) { (result: Result<SubscriptionResponse, APIError>) in
                switch result {
                case .success(let response):
                    Logger.debug("✅ Subscription synced with backend")
                    // A business receipt must never overwrite the consumer
                    // premium status shown in the app
                    if !isBusinessReceipt {
                        self.updateLocalSubscriptionInfo(response.subscription)
                    }
                case .failure(let error):
                    Logger.debug("❌ Failed to sync subscription: \(error)")
                }
            }
        } catch {
            Logger.debug("❌ Failed to read receipt: \(error)")
        }
    }

    /// Sync current subscription with backend (called on app launch and restore)
    func syncCurrentSubscriptionWithBackend() async {
        Logger.debug("🔄 Syncing current subscription with backend...")

        // Skip if user is not logged in
        guard AuthService.shared.isLoggedIn else {
            Logger.debug("💎 Skipping subscription sync - user not logged in")
            return
        }

        // Latest transaction per scope — consumer and business verify
        // separately (the backend routes each by productId)
        var latestConsumer: Transaction? = nil
        var latestBusiness: Transaction? = nil

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            guard transaction.productType == .autoRenewable else {
                continue
            }

            if SubscriptionProduct.isBusinessProductId(transaction.productID) {
                if latestBusiness == nil || transaction.purchaseDate > latestBusiness!.purchaseDate {
                    latestBusiness = transaction
                }
            } else if latestConsumer == nil || transaction.purchaseDate > latestConsumer!.purchaseDate {
                latestConsumer = transaction
            }
        }

        if let transaction = latestConsumer {
            Logger.debug("📱 Found active subscription, syncing with backend...")
            await syncSubscriptionWithBackend(transaction: transaction)
        } else {
            Logger.debug("💎 No active subscription found - checking backend status...")
            // Even if no local subscription, check backend in case it has valid data
            await checkTrialStatus()
        }

        if let transaction = latestBusiness {
            Logger.debug("🏪 Found active business subscription, syncing with backend...")
            await syncSubscriptionWithBackend(transaction: transaction)
        }
    }
    
    private func checkTrialStatus() async {
        // Skip checking trial status if user is not logged in
        guard AuthService.shared.isLoggedIn else {
            Logger.debug("💎 Skipping trial status check - user not logged in")
            return
        }
        
        APIService.shared.request(
            endpoint: "users/subscription/status",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<SubscriptionResponse, APIError>) in
            switch result {
            case .success(let response):
                self?.updateLocalSubscriptionInfo(response.subscription)
            case .failure(let error):
                Logger.debug("❌ Failed to check trial status: \(error)")
                // Stop retrying if unauthorized
                if case .unauthorized = error {
                    Logger.debug("💎 User unauthorized - stopping trial status checks")
                    return
                }
            }
        }
    }
    
    private func updateLocalSubscriptionInfo(_ info: SubscriptionInfo) {
        DispatchQueue.main.async {
            self.subscriptionInfo = info
            self.subscriptionStatus = info.status
        }
    }
    
    // MARK: - Utility Methods
    
    func canCreateMoreCircles(currentCount: Int) -> Bool {
        if subscriptionStatus.isActive {
            return true
        }
        return currentCount < PremiumFeatures.maxFreeCircles
    }
    
    func canAddMorePlaces(currentCount: Int) -> Bool {
        if subscriptionStatus.isActive {
            return true
        }
        return currentCount < PremiumFeatures.maxFreePlacesPerCircle
    }
    
    func canExportContent() -> Bool {
        return subscriptionStatus.isActive
    }
    
    func canShareWithoutWatermark() -> Bool {
        return subscriptionStatus.isActive
    }
}

// MARK: - Error Types

enum SubscriptionError: LocalizedError {
    case verificationFailed
    case purchaseFailed
    case productNotFound
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "Failed to verify purchase"
        case .purchaseFailed:
            return "Purchase could not be completed"
        case .productNotFound:
            return "Subscription product not found"
        case .networkError:
            return "Network error occurred"
        }
    }
}

// MARK: - Response Models

struct SubscriptionResponse: Decodable {
    let success: Bool
    let subscription: SubscriptionInfo
}

