import Foundation
import UIKit

class ReferralService {
    static let shared = ReferralService()
    
    private let apiService = APIService.shared
    private let userDefaults = UserDefaults.standard
    
    // Keys for storing referral data
    private let kPendingReferralCode = "pending_referral_code"
    private let kHasUsedReferralCode = "has_used_referral_code"
    private let kMyReferralCode = "my_referral_code"
    private let kMyReferralCodeUserId = "my_referral_code_user_id"

    private init() {}

    // MARK: - My Referral Code (local cache)

    /// The current user's own referral code, cached locally so share flows can
    /// build invite links synchronously. Scoped to the logged-in user id so a
    /// device that switches accounts never shares the previous account's code.
    var myReferralCode: String? {
        guard let userId = AuthService.shared.getUserId(),
              userDefaults.string(forKey: kMyReferralCodeUserId) == userId else { return nil }
        return userDefaults.string(forKey: kMyReferralCode)
    }

    private func cacheMyReferralCode(_ code: String) {
        guard let userId = AuthService.shared.getUserId() else { return }
        userDefaults.set(code, forKey: kMyReferralCode)
        userDefaults.set(userId, forKey: kMyReferralCodeUserId)
    }

    /// Fetch (creating if needed) the user's referral code so it's ready by the
    /// time they share a connect invite. The backend returns the existing code
    /// when one is already assigned, so this is safe to call repeatedly.
    func prefetchMyReferralCode() {
        guard AuthService.shared.isLoggedIn, myReferralCode == nil else { return }
        generateReferralCode { _ in }
    }
    
    // MARK: - Generate Referral Code
    
    func generateReferralCode(completion: @escaping (Result<String, Error>) -> Void) {
        apiService.request(
            endpoint: "users/referral/generate",
            method: .post,
            body: nil,
            requiresAuth: true
        ) { (result: Result<ReferralResponse, APIError>) in
            switch result {
            case .success(let response):
                self.cacheMyReferralCode(response.referralCode)
                completion(.success(response.referralCode))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Apply Referral Code
    
    func applyReferralCode(_ code: String, completion: @escaping (Result<ApplyReferralResponse, Error>) -> Void) {
        let body = ["referralCode": code]
        
        apiService.request(
            endpoint: "users/referral/apply",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<ApplyReferralResponse, APIError>) in
            switch result {
            case .success(let response):
                self.userDefaults.set(true, forKey: self.kHasUsedReferralCode)
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Get Referral Status
    
    func getReferralStatus(completion: @escaping (Result<ReferralStatus, Error>) -> Void) {
        apiService.request(
            endpoint: "users/referral/status",
            method: .get,
            body: nil,
            requiresAuth: true
        ) { (result: Result<ReferralStatus, APIError>) in
            switch result {
            case .success(let response):
                if let code = response.referralCode {
                    self.cacheMyReferralCode(code)
                }
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Claim Referral Rewards
    
    func claimReferralRewards(completion: @escaping (Result<ClaimRewardsResponse, Error>) -> Void) {
        apiService.request(
            endpoint: "users/referral/claim",
            method: .post,
            body: nil,
            requiresAuth: true
        ) { (result: Result<ClaimRewardsResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Share Referral Link
    
    func shareReferralLink(code: String, from viewController: UIViewController) {
        let message = """
        Join me on Circles! 🌟

        Use my code \(code) to get 1 month free when you sign up.
        """

        // App Store link as its own item so messengers render a tappable
        // rich preview instead of plain text
        let activityViewController = UIActivityViewController(
            activityItems: [message, ShareLinks.appStoreURL],
            applicationActivities: nil
        )
        
        // For iPad
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        viewController.present(activityViewController, animated: true)
    }
    
    // MARK: - Pending Referral Code
    
    func savePendingReferralCode(_ code: String) {
        userDefaults.set(code, forKey: kPendingReferralCode)
    }
    
    func getPendingReferralCode() -> String? {
        return userDefaults.string(forKey: kPendingReferralCode)
    }
    
    func clearPendingReferralCode() {
        userDefaults.removeObject(forKey: kPendingReferralCode)
    }
    
    func hasUsedReferralCode() -> Bool {
        return userDefaults.bool(forKey: kHasUsedReferralCode)
    }
    
    // MARK: - Apply Pending Code After Signup
    
    func applyPendingReferralCodeIfNeeded(completion: @escaping (Bool) -> Void) {
        guard let pendingCode = getPendingReferralCode(),
              !hasUsedReferralCode() else {
            completion(false)
            return
        }
        
        applyReferralCode(pendingCode) { [weak self] result in
            switch result {
            case .success:
                self?.clearPendingReferralCode()
                completion(true)
            case .failure(let error):
                Logger.debug("Failed to apply pending referral code: \(error)")
                completion(false)
            }
        }
    }
}

// MARK: - Response Models

struct ReferralResponse: Codable {
    let success: Bool
    let referralCode: String
    let referralCount: Int
    let referralRewards: [ReferralReward]
}

struct ApplyReferralResponse: Codable {
    let success: Bool
    let message: String
    let referralBenefit: ReferralBenefit?
}

struct ReferralBenefit: Codable {
    let type: String
    let value: Int
}

struct ReferralStatus: Codable {
    let success: Bool
    let referralCode: String?
    let referralCount: Int
    let totalRewards: Int
    let recentRewards: Int
    let unclaimedRewards: Int
    let remainingReferrals: Int
    let referralLink: String?
}

struct ClaimRewardsResponse: Codable {
    let success: Bool
    let message: String
    let daysAdded: Int
    let newExpiryDate: String
}