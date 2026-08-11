import Foundation
import StoreKit
import CryptoKit

@MainActor
class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()
    
    @Published private(set) var products: [SubscriptionProduct] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    /// Starts at `.none` and resolves asynchronously (StoreKit entitlements,
    /// then a backend sync). UIKit screens that gate on it must listen for
    /// `.subscriptionStatusChanged` rather than reading it once — a premium user
    /// briefly looks unsubscribed at launch, which is what made the upgrade
    /// crown flash on the home screen until a tab switch rebuilt the nav bar.
    @Published private(set) var subscriptionStatus: SubscriptionStatus = .none {
        didSet {
            guard oldValue != subscriptionStatus else { return }
            let post = {
                NotificationCenter.default.post(name: .subscriptionStatusChanged, object: nil)
            }
            Thread.isMainThread ? post() : DispatchQueue.main.async(execute: post)
        }
    }
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

    /// Outcome of a purchase attempt. Apple charging the user and the backend
    /// recording the entitlement are separate steps — callers must not tell
    /// the user "you're all set" unless `backendSynced` is true.
    enum PurchaseResult {
        case success(Transaction, backendSynced: Bool)
        case cancelled
        /// Ask to Buy / deferred — approval arrives later via Transaction.updates
        case pending
    }

    /// `venueId`: for Business products, the venue this subscription is being
    /// purchased for — each store subscribes separately, and the backend binds
    /// the entitlement to this one venue.
    func purchase(_ product: SubscriptionProduct, venueId: String? = nil) async throws -> PurchaseResult {
        do {
            // Stamp the purchase with a token derived from the app account, so
            // Apple's server notifications can be matched to this user even for
            // a first-ever subscription (an origTx no account holds yet)
            var options: Set<Product.PurchaseOption> = []
            if let userId = AuthService.shared.currentUser?.id {
                options.insert(.appAccountToken(Self.appAccountToken(for: userId)))
            }
            let result = try await product.product.purchase(options: options)

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)

                // Update subscription status
                await updateSubscriptionStatus()

                // Sync with backend BEFORE finishing: an unfinished transaction
                // is redelivered by StoreKit on the next launch, which gives a
                // failed backend sync a natural retry instead of stranding a
                // paid-but-unrecorded subscription.
                let synced = await syncSubscriptionWithBackend(
                    transaction: transaction,
                    venueId: venueId,
                    attempts: 3,
                    signedTransaction: verification.jwsRepresentation
                )
                if synced {
                    await transaction.finish()
                }

                return .success(transaction, backendSynced: synced)

            case .userCancelled:
                Logger.debug("⚠️ User cancelled purchase")
                return .cancelled

            case .pending:
                Logger.debug("⏳ Purchase pending (Ask to Buy) — will land via Transaction.updates")
                return .pending

            @unknown default:
                Logger.debug("❓ Unknown purchase result")
                return .cancelled
            }
        } catch {
            Logger.debug("❌ Purchase failed: \(error)")
            throw error
        }
    }

    // MARK: - Restore Purchases

    /// `venueId`: when restoring from a venue's paywall, lets the backend bind
    /// a not-yet-bound business subscription to that venue.
    func restorePurchases(venueId: String? = nil) async throws {
        try await AppStore.sync()
        await updateSubscriptionStatus()

        // Sync with backend after restore
        await syncCurrentSubscriptionWithBackend(venueId: venueId)
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
            // Renewals, revocations, purchases approved after Ask to Buy, and
            // purchases made on other devices all arrive here. Each one must
            // reach the backend, and is only finished once the backend has it
            // (unfinished transactions redeliver on next launch = free retry).
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await updateSubscriptionStatus()
                let synced = await syncSubscriptionWithBackend(
                    transaction: transaction,
                    signedTransaction: update.jwsRepresentation
                )
                if synced {
                    await transaction.finish()
                }
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

    // MARK: - App Account Token

    // Load-bearing constant: purchases are permanently stamped with tokens
    // derived from it. Changing it orphans every token already sent to Apple.
    private static let appAccountTokenNamespace = UUID(uuidString: "9A1F9C3D-6B2E-4A54-8D2B-4E1C3F7A5B60")!

    /// Deterministic UUID (v5, SHA-1 name-based) derived from the user's id —
    /// the same account always yields the same token, letting the backend match
    /// App Store server notifications to the purchasing user even for a
    /// first-ever subscription.
    static func appAccountToken(for userId: String) -> UUID {
        var data = Data()
        withUnsafeBytes(of: appAccountTokenNamespace.uuid) { data.append(contentsOf: $0) }
        data.append(Data(userId.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        let uuid: uuid_t = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: uuid)
    }
    
    // MARK: - Backend Sync
    
    /// Sends the receipt (+ venueId for business purchases) to the backend and
    /// AWAITS the result — success means the server recorded the entitlement.
    /// Retries with backoff; returns false only after every attempt failed.
    @discardableResult
    private func syncSubscriptionWithBackend(
        transaction: Transaction,
        venueId: String? = nil,
        attempts: Int = 1,
        signedTransaction: String? = nil
    ) async -> Bool {
        // The legacy receipt is NOT guaranteed to contain a StoreKit 2 purchase
        // that just happened (especially a brand-new subscription) — the signed
        // transaction JWS is the authoritative proof, so its absence is only
        // fatal when there's no receipt either.
        let receiptString = await loadReceiptBase64()
        if receiptString == nil && signedTransaction == nil {
            Logger.debug("❌ No app receipt and no signed transaction — backend sync skipped")
            return false
        }

        var body: [String: Any] = [
            "transactionId": transaction.id,
            "productId": transaction.productID,
            "originalTransactionId": transaction.originalID,
            "purchaseDate": ISO8601DateFormatter().string(from: transaction.purchaseDate),
            "expirationDate": transaction.expirationDate.map { ISO8601DateFormatter().string(from: $0) } ?? nil
        ]
        if let receiptString = receiptString {
            body["receipt"] = receiptString
        }
        if let signedTransaction = signedTransaction {
            body["signedTransaction"] = signedTransaction
        }
        // Business purchases bind to the venue they were bought for
        if let venueId = venueId {
            body["venueId"] = venueId
        }

        let isBusinessReceipt = SubscriptionProduct.isBusinessProductId(transaction.productID)
        let totalAttempts = max(1, attempts)

        for attempt in 1...totalAttempts {
            let succeeded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
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
                        continuation.resume(returning: true)
                    case .failure(let error):
                        Logger.debug("❌ Failed to sync subscription (attempt \(attempt)/\(totalAttempts)): \(error)")
                        continuation.resume(returning: false)
                    }
                }
            }
            if succeeded { return true }
            if attempt < totalAttempts {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
            }
        }
        return false
    }

    /// The backend's verifyReceipt consumes the legacy app-receipt file, which
    /// StoreKit 2 does not guarantee exists. Refresh it once if missing.
    private func loadReceiptBase64() async -> String? {
        if let receipt = readReceiptBase64() { return receipt }
        Logger.debug("🧾 App receipt missing — requesting a receipt refresh")
        await ReceiptRefresher.refresh()
        return readReceiptBase64()
    }

    private func readReceiptBase64() -> String? {
        guard let url = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return data.base64EncodedString()
    }

    /// Sync current subscription with backend (called on app launch, login,
    /// and restore). `venueId` lets a venue-scoped restore bind an unbound
    /// business subscription.
    func syncCurrentSubscriptionWithBackend(venueId: String? = nil) async {
        Logger.debug("🔄 Syncing current subscription with backend...")

        // Skip if user is not logged in
        guard AuthService.shared.isLoggedIn else {
            Logger.debug("💎 Skipping subscription sync - user not logged in")
            return
        }

        // Latest transaction per scope — consumer and business verify
        // separately (the backend routes each by productId). Keep the JWS
        // alongside: it's the proof the backend can verify even when the
        // legacy receipt is stale.
        var latestConsumer: (transaction: Transaction, jws: String)? = nil
        var latestBusiness: (transaction: Transaction, jws: String)? = nil

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            guard transaction.productType == .autoRenewable else {
                continue
            }

            if SubscriptionProduct.isBusinessProductId(transaction.productID) {
                if latestBusiness == nil || transaction.purchaseDate > latestBusiness!.transaction.purchaseDate {
                    latestBusiness = (transaction, result.jwsRepresentation)
                }
            } else if latestConsumer == nil || transaction.purchaseDate > latestConsumer!.transaction.purchaseDate {
                latestConsumer = (transaction, result.jwsRepresentation)
            }
        }

        if let (transaction, jws) = latestConsumer {
            Logger.debug("📱 Found active subscription, syncing with backend...")
            await syncSubscriptionWithBackend(transaction: transaction, signedTransaction: jws)
        } else {
            Logger.debug("💎 No active subscription found - checking backend status...")
            // Even if no local subscription, check backend in case it has valid data
            await checkTrialStatus()
        }

        if let (transaction, jws) = latestBusiness {
            Logger.debug("🏪 Found active business subscription, syncing with backend...")
            await syncSubscriptionWithBackend(transaction: transaction, venueId: venueId, signedTransaction: jws)
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

// MARK: - Receipt Refresh (legacy StoreKit 1 API — StoreKit 2 has no
// receipt-refresh equivalent, and the backend consumes the legacy receipt file)

private final class ReceiptRefresher: NSObject, SKRequestDelegate {
    // SKRequest.delegate is unsafe-unretained; keep the in-flight refresher
    // alive until its callback fires.
    private static var active: ReceiptRefresher?

    private var continuation: CheckedContinuation<Void, Never>?
    private var request: SKReceiptRefreshRequest?

    static func refresh() async {
        let refresher = ReceiptRefresher()
        active = refresher
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            refresher.continuation = continuation
            let request = SKReceiptRefreshRequest()
            refresher.request = request
            request.delegate = refresher
            request.start()
        }
        active = nil
    }

    func requestDidFinish(_ request: SKRequest) {
        finish()
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        Logger.debug("🧾 Receipt refresh failed: \(error)")
        finish()
    }

    private func finish() {
        request?.delegate = nil
        request = nil
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - Response Models

struct SubscriptionResponse: Decodable {
    let success: Bool
    let subscription: SubscriptionInfo
}

