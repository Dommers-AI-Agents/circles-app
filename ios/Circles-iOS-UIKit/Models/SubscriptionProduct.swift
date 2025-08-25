import Foundation
import StoreKit

struct SubscriptionProduct {
    static let monthlyProductId = "com.favcircles.circles.premium.subscription.monthly"
    static let annualProductId = "com.favcircles.circles.premium.annual"
    
    let product: Product
    let subscription: Product.SubscriptionInfo?
    
    init(product: Product) {
        self.product = product
        self.subscription = product.subscription
    }
    
    var id: String {
        product.id
    }
    
    var displayName: String {
        product.displayName
    }
    
    var displayPrice: String {
        product.displayPrice
    }
    
    var price: Decimal {
        product.price
    }
    
    var periodUnit: Product.SubscriptionPeriod.Unit? {
        subscription?.subscriptionPeriod.unit
    }
    
    var periodValue: Int? {
        subscription?.subscriptionPeriod.value
    }
    
    var hasFreeTrial: Bool {
        subscription?.introductoryOffer?.paymentMode == .freeTrial
    }
    
    var freeTrialPeriod: String? {
        guard let offer = subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        
        let period = offer.period
        switch period.unit {
        case .day:
            return period.value == 1 ? "1 day" : "\(period.value) days"
        case .week:
            return period.value == 1 ? "1 week" : "\(period.value) weeks"
        case .month:
            return period.value == 1 ? "1 month" : "\(period.value) months"
        case .year:
            return period.value == 1 ? "1 year" : "\(period.value) years"
        @unknown default:
            return nil
        }
    }
    
    var subscriptionDescription: String {
        var description = displayPrice
        
        if let unit = periodUnit {
            switch unit {
            case .day:
                description += "/day"
            case .week:
                description += "/week"
            case .month:
                description += "/month"
            case .year:
                description += "/year"
            @unknown default:
                break
            }
        }
        
        if let trialPeriod = freeTrialPeriod {
            description += " after \(trialPeriod) free trial"
        }
        
        return description
    }
    
    // MARK: - Tier Information
    
    var isMonthly: Bool {
        product.id == SubscriptionProduct.monthlyProductId
    }
    
    var isAnnual: Bool {
        product.id == SubscriptionProduct.annualProductId
    }
    
    var tierName: String {
        if isMonthly {
            return "Monthly"
        } else if isAnnual {
            return "Annual"
        } else {
            return "Premium"
        }
    }
    
    var savingsPercentage: Int? {
        guard isAnnual else { return nil }
        
        // Calculate savings: (monthly * 12 - annual) / (monthly * 12) * 100
        let monthlyPrice: Decimal = 2.99
        let annualizedMonthly = monthlyPrice * 12
        let annualPrice = price
        
        let savings = (annualizedMonthly - annualPrice) / annualizedMonthly * 100
        return Int(truncating: NSDecimalNumber(decimal: savings))
    }
    
    var pricePerMonth: String? {
        guard isAnnual else { return nil }
        
        let monthlyAmount = price / 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceFormatStyle.locale
        
        if let formattedPrice = formatter.string(from: NSDecimalNumber(decimal: monthlyAmount)) {
            return "\(formattedPrice)/month"
        }
        return nil
    }
    
    var badgeText: String? {
        if isAnnual && savingsPercentage != nil {
            return "BEST VALUE"
        }
        return nil
    }
}

// Premium features configuration
struct PremiumFeatures {
    static let maxFreeCircles = 6
    static let maxFreePlacesPerCircle = 15
    
    struct Feature {
        let title: String
        let description: String
        let iconName: String
    }
    
    static let features: [Feature] = [
        Feature(
            title: "Unlimited Circles",
            description: "Create as many circles as you want",
            iconName: "infinity.circle.fill"
        ),
        Feature(
            title: "Unlimited Places",
            description: "Add unlimited places to each circle",
            iconName: "mappin.circle.fill"
        ),
        Feature(
            title: "Export & Share",
            description: "Export your circles and share without watermarks",
            iconName: "square.and.arrow.up.circle.fill"
        ),
        Feature(
            title: "Priority Support",
            description: "Get help faster with priority customer support",
            iconName: "person.2.circle.fill"
        ),
        Feature(
            title: "Advanced Features",
            description: "Access to new features as they're released",
            iconName: "sparkles.rectangle.stack.fill"
        )
    ]
}