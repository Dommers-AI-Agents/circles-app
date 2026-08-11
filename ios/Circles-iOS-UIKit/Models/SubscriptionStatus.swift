import Foundation
import UIKit

enum SubscriptionStatus: String, Codable {
    case none = "none"
    case trial = "trial"
    case active = "active"
    // Billing retry — Apple keeps entitlement alive while retrying payment
    case gracePeriod = "grace_period"
    case expired = "expired"
    case cancelled = "cancelled"

    /// A status string this build doesn't know must never fail the whole
    /// response decode (that reads as "sync failed" to callers) — fall back
    /// to .none instead.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SubscriptionStatus(rawValue: raw) ?? .none
    }

    var isActive: Bool {
        switch self {
        case .trial, .active, .gracePeriod:
            return true
        case .none, .expired, .cancelled:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .none:
            return "Free"
        case .trial:
            return "Free Trial"
        case .active:
            return "Premium"
        case .gracePeriod:
            return "Premium"
        case .expired:
            return "Expired"
        case .cancelled:
            return "Cancelled"
        }
    }

    var badgeColor: UIColor {
        switch self {
        case .none:
            return Constants.Colors.secondaryLabel
        case .trial, .gracePeriod:
            return .systemOrange
        case .active:
            return Constants.Colors.primary
        case .expired, .cancelled:
            return .systemRed
        }
    }
}

struct SubscriptionInfo: Codable {
    let status: SubscriptionStatus
    let expiryDate: Date?
    let trialStartDate: Date?
    let trialEndDate: Date?
    // Optional: guard/ignored responses from the backend omit it, and that
    // must not fail the decode
    let autoRenewEnabled: Bool?
    let productId: String?
    
    var daysLeftInTrial: Int? {
        guard status == .trial, let trialEnd = trialEndDate else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
        return max(0, days)
    }
    
    var isExpiringSoon: Bool {
        guard let expiry = expiryDate else { return false }
        let daysUntilExpiry = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        return daysUntilExpiry <= 3 && daysUntilExpiry >= 0
    }
}