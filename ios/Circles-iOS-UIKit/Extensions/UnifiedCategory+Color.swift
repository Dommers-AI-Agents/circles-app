import UIKit

extension UnifiedCategory {
    var color: UIColor {
        switch self {
        case .standard(let category):
            return category.color
        case .custom:
            return UIColor(hex: "#718096") // Gray for custom categories
        }
    }
}
