import UIKit

struct Constants {
    struct Colors {
        // Primary brand colors - using dynamic colors for better dark mode support
        static let primary = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 0.39, green: 0.7, blue: 0.93, alpha: 1.0) // Lighter blue for dark mode
            } else {
                return UIColor(red: 0.2, green: 0.51, blue: 0.81, alpha: 1.0) // #3182CE
            }
        }
        
        static let secondary = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 0.5, green: 0.78, blue: 0.95, alpha: 1.0) // Even lighter for dark mode
            } else {
                return UIColor(red: 0.39, green: 0.7, blue: 0.93, alpha: 1.0) // #63B3ED
            }
        }
        
        static let accent = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 0.41, green: 0.87, blue: 0.82, alpha: 1.0) // Brighter for dark mode
            } else {
                return UIColor(red: 0.31, green: 0.82, blue: 0.77, alpha: 1.0) // #4FD1C5
            }
        }
        
        // System adaptive colors for better dark mode support
        static let background = UIColor.systemBackground
        static let secondaryBackground = UIColor.secondarySystemBackground
        static let tertiaryBackground = UIColor.tertiarySystemBackground
        static let groupedBackground = UIColor.systemGroupedBackground
        
        // Text colors that adapt to dark mode
        static let label = UIColor.label
        static let secondaryLabel = UIColor.secondaryLabel
        static let tertiaryLabel = UIColor.tertiaryLabel
        static let placeholderText = UIColor.placeholderText
        
        // Legacy color references (kept for backward compatibility)
        static let white = UIColor.white
        static let black = UIColor.black
        
        // System grays that adapt to dark mode
        static let gray = UIColor.systemGray
        static let mediumGray = UIColor.systemGray2
        static let lightGray = UIColor.systemGray5
        static let darkGray = UIColor.systemGray3
        
        // Separator and border colors
        static let separator = UIColor.separator
        static let opaqueSeparator = UIColor.opaqueSeparator
        
        // Semantic colors with dark mode support
        static let danger = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 0.95, green: 0.4, blue: 0.4, alpha: 1.0) // Brighter red for dark mode
            } else {
                return UIColor(red: 0.9, green: 0.24, blue: 0.24, alpha: 1.0) // #E53E3E
            }
        }
        
        static let success = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 0.32, green: 0.73, blue: 0.51, alpha: 1.0) // Brighter green for dark mode
            } else {
                return UIColor(red: 0.22, green: 0.63, blue: 0.41, alpha: 1.0) // #38A169
            }
        }
        
        static let warning = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 0.95, green: 0.84, blue: 0.4, alpha: 1.0) // Brighter yellow for dark mode
            } else {
                return UIColor(red: 0.93, green: 0.79, blue: 0.29, alpha: 1.0) // #ECC94B
            }
        }
        
        static let info = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 0.4, green: 0.7, blue: 0.92, alpha: 1.0) // Brighter blue for dark mode
            } else {
                return UIColor(red: 0.26, green: 0.6, blue: 0.88, alpha: 1.0) // #4299E1
            }
        }
        
        // Bright orange for pending connection requests - more visible than system orange
        static let brightOrange = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 1.0) // #FFA500 for dark mode
            } else {
                return UIColor(red: 1.0, green: 0.52, blue: 0.0, alpha: 1.0) // #FF8500 for light mode
            }
        }
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
