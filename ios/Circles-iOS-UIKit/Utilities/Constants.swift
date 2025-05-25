import UIKit

struct Constants {
    struct Colors {
        static let primary = UIColor(red: 0.2, green: 0.51, blue: 0.81, alpha: 1.0) // #3182CE
        static let secondary = UIColor(red: 0.39, green: 0.7, blue: 0.93, alpha: 1.0) // #63B3ED
        static let accent = UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1.0) // #4FD1C5
        static let background = UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0) // #F7FAFC
        static let white = UIColor.white
        static let black = UIColor.black
        static let gray = UIColor(red: 0.44, green: 0.5, blue: 0.59, alpha: 1.0) // #718096
        static let lightGray = UIColor(red: 0.89, green: 0.91, blue: 0.94, alpha: 1.0) // #E2E8F0
        static let darkGray = UIColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1.0) // #2D3748
        static let danger = UIColor(red: 0.9, green: 0.24, blue: 0.24, alpha: 1.0) // #E53E3E
        static let success = UIColor(red: 0.22, green: 0.63, blue: 0.41, alpha: 1.0) // #38A169
        static let warning = UIColor(red: 0.93, green: 0.79, blue: 0.29, alpha: 1.0) // #ECC94B
        static let info = UIColor(red: 0.26, green: 0.6, blue: 0.88, alpha: 1.0) // #4299E1
    }
    
    struct FontSize {
        static let xsmall: CGFloat = 10
        static let small: CGFloat = 12
        static let medium: CGFloat = 14
        static let large: CGFloat = 16
        static let xlarge: CGFloat = 18
        static let xxlarge: CGFloat = 20
        static let xxxlarge: CGFloat = 24
        static let huge: CGFloat = 30
    }
    
    struct Spacing {
        static let tiny: CGFloat = 4
        static let xsmall: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xlarge: CGFloat = 32
        static let xxlarge: CGFloat = 40
        static let xxxlarge: CGFloat = 56
        static let huge: CGFloat = 72
    }
    
    struct Images {
        static let defaultProfileImage = UIImage(systemName: "person.circle")
        static let defaultCoverImage = UIImage(systemName: "photo")
        static let defaultPlaceImage = UIImage(systemName: "mappin.circle")
    }
}
