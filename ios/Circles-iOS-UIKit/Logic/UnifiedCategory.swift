import Foundation

// MARK: - Unified Category System
enum UnifiedCategory: Hashable, Equatable {
    case standard(PlaceCategory)
    case custom(String) // Custom category name
    
    var displayName: String {
        switch self {
        case .standard(let category):
            return category.displayName
        case .custom(let name):
            return name
        }
    }
    
    var isCustom: Bool {
        switch self {
        case .standard:
            return false
        case .custom:
            return true
        }
    }
    
    var systemIconName: String {
        switch self {
        case .standard(let category):
            return category.systemIconName
        case .custom:
            return "tag.fill" // Default icon for custom categories
        }
    }
    
    
    // Helper to match against a Place
    func matches(place: Place) -> Bool {
        switch self {
        case .standard(let category):
            return place.category == category
        case .custom(let name):
            // Custom categories are stored as: category: .other, customCategoryId: "Category Name"
            let matches = place.category == .other && place.customCategoryId == name
            
            // Debug logging for custom category matching
            if !matches {
                Logger.debug("🚫 Custom category '\(name)' does not match place '\(place.name)' - place category: \(place.category.rawValue), customCategoryId: '\(place.customCategoryId ?? "none")'")
            } else {
                Logger.debug("✅ Custom category '\(name)' matches place '\(place.name)'")
            }
            
            return matches
        }
    }
    
    // Helper to create from a Place
    static func from(place: Place) -> UnifiedCategory {
        if place.category == .other, let customName = place.customCategoryId, !customName.isEmpty {
            // Validate that this is actually a category name and not user data
            if isValidCategoryName(customName) {
                // Check for custom categories that should map to standard categories
                if let standardCategory = mapCustomToStandardCategory(customName) {
                    return .standard(standardCategory)
                }
                return .custom(customName)
            } else {
                // Fall back to "Other" category if invalid
                Logger.debug("⚠️ Invalid custom category detected: '\(customName)' - falling back to Other")
                return .standard(.other)
            }
        } else {
            return .standard(place.category)
        }
    }
    
    // Map custom category names to standard categories to prevent duplicates
    private static func mapCustomToStandardCategory(_ customName: String) -> PlaceCategory? {
        let normalizedName = customName.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Healthcare variations
        if normalizedName == "healthcare" || normalizedName == "health care" || normalizedName == "medical" {
            return .healthcare
        }
        
        // Restaurant variations  
        if normalizedName == "restaurant" || normalizedName == "restaurants" {
            return .restaurant
        }
        
        // Cafe variations
        if normalizedName == "cafe" || normalizedName == "café" || normalizedName == "coffee" {
            return .cafe
        }
        
        // Bar variations
        if normalizedName == "bar" || normalizedName == "bars" || normalizedName == "pub" {
            return .bar
        }
        
        // Retail variations
        if normalizedName == "retail" || normalizedName == "shopping" || normalizedName == "store" {
            return .retail
        }
        
        // Hotel variations
        if normalizedName == "hotel" || normalizedName == "accommodation" || normalizedName == "lodging" {
            return .hotel
        }
        
        // Service variations
        if normalizedName == "service" || normalizedName == "services" {
            return .service
        }
        
        // Entertainment variations
        if normalizedName == "entertainment" || normalizedName == "nightclub" {
            return .entertainment
        }
        
        // Fitness variations
        if normalizedName == "fitness" || normalizedName == "gym" || normalizedName == "health club" {
            return .fitness
        }
        
        // Attraction variations
        if normalizedName == "attraction" || normalizedName == "tourist" || normalizedName == "sightseeing" {
            return .attraction
        }
        
        // Home variations
        if normalizedName == "home" || normalizedName == "house" || normalizedName == "residence" {
            return .home
        }
        
        // Work variations
        if normalizedName == "work" || normalizedName == "office" || normalizedName == "workplace" {
            return .work
        }
        
        return nil // No mapping found, keep as custom category
    }
    
    // Validate that a string is a valid category name (not an email or user ID)
    private static func isValidCategoryName(_ name: String) -> Bool {
        // Check if it looks like an email
        if name.contains("@") && name.contains(".") {
            return false
        }
        
        // Check if it's a numeric ID
        if name.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil && name.count > 10 {
            return false
        }
        
        // Check if it contains typical user name patterns (firstname lastname)
        let components = name.components(separatedBy: " ")
        if components.count == 2 {
            // Check if both components start with capital letters (typical for names)
            let firstComponent = components[0]
            let secondComponent = components[1]
            if !firstComponent.isEmpty && !secondComponent.isEmpty {
                let firstChar = String(firstComponent.prefix(1))
                let secondChar = String(secondComponent.prefix(1))
                if firstChar == firstChar.uppercased() && secondChar == secondChar.uppercased() {
                    // Likely a person's name, not a category
                    return false
                }
            }
        }
        
        // Additional checks for known invalid patterns
        let invalidPatterns = ["admin", "user", "test"]
        let lowercaseName = name.lowercased()
        for pattern in invalidPatterns {
            if lowercaseName == pattern {
                return false
            }
        }
        
        return true
    }
}
