import Foundation
import UIKit

enum SubscriptionStatus: String, Codable {
    case none = "none"
    case trial = "trial"
    case active = "active"
    case expired = "expired"
    case cancelled = "cancelled"
    
    var isActive: Bool {
        switch self {
        case .trial, .active:
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
        case .trial:
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
    let autoRenewEnabled: Bool
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