import Foundation
import StoreKit

@MainActor
class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()
    
    @Published private(set) var products: [SubscriptionProduct] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    @Published private(set) var subscriptionStatus: SubscriptionStatus = .none
    @Published private(set) var subscriptionInfo: SubscriptionInfo?
    
    private var productIds = [
        SubscriptionProduct.monthlyProductId,
        SubscriptionProduct.annualProductId
    ]
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
        print("🔍 [SubscriptionService] Starting to load products...")
        print("🔍 Product IDs to request: \(productIds)")
        print("🔍 Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        
        do {
            print("📱 Requesting products from StoreKit...")
            let storeProducts = try await Product.products(for: productIds)
            
            print("📦 Received \(storeProducts.count) products from StoreKit")
            
            for product in storeProducts {
                print("  ✅ Product loaded:")
                print("     - ID: \(product.id)")
                print("     - Display Name: \(product.displayName)")
                print("     - Display Price: \(product.displayPrice)")
                print("     - Type: \(product.type.rawValue)")
                if let subscription = product.subscription {
                    print("     - Period: \(subscription.subscriptionPeriod)")
                    print("     - Period Unit: \(subscription.subscriptionPeriod.unit)")
                    print("     - Period Value: \(subscription.subscriptionPeriod.value)")
                }
            }
            
            products = storeProducts
                .map { SubscriptionProduct(product: $0) }
                .sorted { $0.price < $1.price }
            
            print("✅ Successfully loaded and sorted \(products.count) subscription products")
            
            if products.isEmpty {
                print("⚠️ WARNING: No products loaded. Possible reasons:")
                print("   1. Products not configured in App Store Connect")
                print("   2. Bundle ID mismatch")
                print("   3. Products still processing (can take up to 24 hours)")
                print("   4. Not signed in with sandbox account (for testing)")
                print("   5. Paid Applications agreement not active")
            }
        } catch {
            print("❌ Failed to load products from StoreKit")
            print("❌ Error type: \(type(of: error))")
            print("❌ Error description: \(error.localizedDescription)")
            
            if let skError = error as? StoreKitError {
                print("❌ StoreKit Error: \(skError)")
                switch skError {
                case .networkError(let urlError):
                    print("   - Network error: \(urlError)")
                case .systemError(let nsError):
                    print("   - System error: \(nsError)")
                case .userCancelled:
                    print("   - User cancelled")
                default:
                    print("   - Other StoreKit error")
                }
            } else if let nsError = error as NSError? {
                print("❌ NSError details:")
                print("   - Domain: \(nsError.domain)")
                print("   - Code: \(nsError.code)")
                print("   - User Info: \(nsError.userInfo)")
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
                print("⚠️ User cancelled purchase")
                return nil
                
            case .pending:
                print("⏳ Purchase pending")
                return nil
                
            @unknown default:
                print("❓ Unknown purchase result")
                return nil
            }
        } catch {
            print("❌ Purchase failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchases() async throws {
        try await AppStore.sync()
        await updateSubscriptionStatus()
    }
    
    // MARK: - Check Subscription Status
    
    func updateSubscriptionStatus() async {
        var highestStatus: Product.SubscriptionInfo.Status? = nil
        var highestProduct: Product? = nil
        
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }
            
            guard transaction.productType == .autoRenewable else {
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
            print("❌ No receipt found")
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
            
            APIService.shared.request(
                endpoint: "users/subscription/verify",
                method: .post,
                body: body,
                requiresAuth: true
            ) { (result: Result<SubscriptionResponse, APIError>) in
                switch result {
                case .success(let response):
                    print("✅ Subscription synced with backend")
                    self.updateLocalSubscriptionInfo(response.subscription)
                case .failure(let error):
                    print("❌ Failed to sync subscription: \(error)")
                }
            }
        } catch {
            print("❌ Failed to read receipt: \(error)")
        }
    }
    
    private func checkTrialStatus() async {
        APIService.shared.request(
            endpoint: "users/subscription/status",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<SubscriptionResponse, APIError>) in
            switch result {
            case .success(let response):
                self?.updateLocalSubscriptionInfo(response.subscription)
            case .failure(let error):
                print("❌ Failed to check trial status: \(error)")
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

