import Foundation

/// User-facing category groups for the browse filter chips. Maps the underlying
/// PlaceCategory enum into friendly buckets (Food = restaurant, Coffee = cafe,
/// Drinks = bar, …). Filtering narrows by category across ALL circles.
enum PlaceCategoryGroup: String, CaseIterable {
    case all, food, coffee, drinks, shopping, fitness, hotels, attractions
    case fun, outdoors, health, services, learning, transit, finance, other

    var title: String {
        switch self {
        case .all: return "All"
        case .food: return "Food"
        case .coffee: return "Coffee"
        case .drinks: return "Drinks"
        case .shopping: return "Shopping"
        case .fitness: return "Fitness"
        case .hotels: return "Hotels"
        case .attractions: return "Attractions"
        case .fun: return "Fun"
        case .outdoors: return "Outdoors"
        case .health: return "Health"
        case .services: return "Services"
        case .learning: return "Learning"
        case .transit: return "Transit"
        case .finance: return "Finance"
        case .other: return "Other"
        }
    }

    /// Underlying PlaceCategory raw values this group represents.
    var categories: Set<String> {
        switch self {
        case .all: return []
        case .food: return ["restaurant"]
        case .coffee: return ["cafe"]
        case .drinks: return ["bar"]
        case .shopping: return ["retail"]
        case .fitness: return ["fitness"]
        case .hotels: return ["hotel"]
        case .attractions: return ["attraction"]
        case .fun: return ["entertainment"]
        case .outdoors: return ["outdoor"]
        case .health: return ["healthcare"]
        case .services: return ["service"]
        case .learning: return ["education"]
        case .transit: return ["transport"]
        case .finance: return ["finance"]
        case .other: return ["other", "home", "work"]
        }
    }

    func matches(_ category: String) -> Bool {
        self == .all ? true : categories.contains(category)
    }

    /// The group a raw category belongs to (falls back to `.other`).
    static func group(for category: String) -> PlaceCategoryGroup {
        allCases.first { $0 != .all && $0.categories.contains(category) } ?? .other
    }

    /// Groups actually present in a set of venue categories, in canonical order,
    /// with `.all` first. Drives adaptive chips (only show what has content).
    static func present(in categories: [String]) -> [PlaceCategoryGroup] {
        let present = Set(categories.map { group(for: $0) })
        return [.all] + allCases.filter { $0 != .all && present.contains($0) }
    }
}
