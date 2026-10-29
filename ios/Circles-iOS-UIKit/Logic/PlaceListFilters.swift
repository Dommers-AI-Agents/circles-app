import Foundation

// MARK: - Place Array Filtering Extensions
extension Array where Element == Place {
    // Filter by category
    func filtered(by category: UnifiedCategory?) -> [Place] {
        guard let category = category else { return self }
        return self.filter { category.matches(place: $0) }
    }
    
    // Filter by connection (for "My Places Only" etc)
    func filtered(by connectionId: String?, currentUserId: String) -> [Place] {
        guard let connectionId = connectionId else { return self }
        
        if connectionId == "my_places_only" {
            // Show only user's own places
            return self.filter { $0.addedBy == currentUserId }
        } else {
            // Show only places from the selected connection
            return self.filter { $0.addedBy == connectionId }
        }
    }
    
    // Filter by city
    func filtered(by city: String?) -> [Place] {
        guard let city = city else { return self }
        // lensCity prefers the server-derived city and handles every address
        // format (the old component parse landed on the ZIP for Apple-style
        // "..., City, ST, 12345, United States" addresses).
        return self.filter { place in
            place.lensCity?.localizedCaseInsensitiveCompare(city) == .orderedSame
        }
    }
    
    // Combined filter method
    func filtered(category: UnifiedCategory? = nil,
                 connectionId: String? = nil,
                 city: String? = nil,
                 currentUserId: String) -> [Place] {
        var result = self
        
        // Apply filters in sequence
        result = result.filtered(by: category)
        result = result.filtered(by: connectionId, currentUserId: currentUserId)
        result = result.filtered(by: city)
        
        return result
    }
}

// MARK: - Category Utilities
extension PlaceCategory {
    // Get all unique categories from a list of places
    static func uniqueCategories(from places: [Place]) -> [UnifiedCategory] {
        var categoriesSet = Set<UnifiedCategory>()
        
        for place in places {
            categoriesSet.insert(UnifiedCategory.from(place: place))
        }
        
        return categoriesSet.sorted(by: { $0.displayName < $1.displayName })
    }
}

// MARK: - Place Utilities
extension Array where Element == Place {
    // Get available cities from places
    func uniqueCities() -> [String] {
        var citiesSet = Set<String>()
        
        for place in self {
            // Extract city from address (assumes format: "..., City, State/Country")
            let components = place.address.components(separatedBy: ", ")
            if components.count >= 2 {
                let city = components[components.count - 2].trimmingCharacters(in: .whitespaces)
                if !city.isEmpty {
                    citiesSet.insert(city)
                }
            }
        }
        
        return citiesSet.sorted()
    }
}
