import Foundation

/// Maps Google Places `types` onto the app's category and an optional
/// subcategory label, for prefilling the add-place form.
enum PlaceCategoryMapper {
    struct Mapping: Equatable {
        let category: PlaceCategory
        let subcategory: String?
    }

    /// First matching rule wins, in this order.
    static func mapping(forGoogleTypes types: [String]) -> Mapping {
        if types.contains("restaurant") || types.contains("food") {
            // Try to set subcategory based on more specific types
            if types.contains("meal_takeaway") || types.contains("meal_delivery") {
                return Mapping(category: .restaurant, subcategory: "Fast Food")
            } else if types.contains("bakery") {
                return Mapping(category: .restaurant, subcategory: "Bakery")
            }
            return Mapping(category: .restaurant, subcategory: nil)
        } else if types.contains("cafe") {
            return Mapping(category: .cafe, subcategory: types.contains("coffee_shop") ? "Coffee Shop" : nil)
        } else if types.contains("bar") || types.contains("night_club") {
            return Mapping(category: .bar, subcategory: types.contains("night_club") ? "Nightclub" : nil)
        } else if types.contains("lodging") || types.contains("hotel") {
            return Mapping(category: .hotel, subcategory: nil)
        } else if types.contains("store") || types.contains("shopping_mall") {
            if types.contains("grocery_or_supermarket") {
                return Mapping(category: .retail, subcategory: "Grocery Store")
            } else if types.contains("clothing_store") {
                return Mapping(category: .retail, subcategory: "Clothing Store")
            } else if types.contains("electronics_store") {
                return Mapping(category: .retail, subcategory: "Electronics")
            }
            return Mapping(category: .retail, subcategory: nil)
        } else if types.contains("beauty_salon") || types.contains("hair_care") || types.contains("spa") {
            if types.contains("beauty_salon") {
                return Mapping(category: .service, subcategory: "Beauty Salon")
            } else if types.contains("hair_care") {
                return Mapping(category: .service, subcategory: "Hair Salon")
            }
            return Mapping(category: .service, subcategory: "Spa")
        } else if types.contains("gym") || types.contains("health") {
            return Mapping(category: .fitness, subcategory: types.contains("gym") ? "Gym" : nil)
        } else if types.contains("doctor") || types.contains("hospital") || types.contains("pharmacy") {
            if types.contains("doctor") {
                return Mapping(category: .healthcare, subcategory: "Doctor")
            } else if types.contains("hospital") {
                return Mapping(category: .healthcare, subcategory: "Hospital")
            }
            return Mapping(category: .healthcare, subcategory: "Pharmacy")
        } else if types.contains("tourist_attraction") || types.contains("museum") || types.contains("park") {
            if types.contains("museum") {
                return Mapping(category: .attraction, subcategory: "Museum")
            } else if types.contains("park") {
                return Mapping(category: .attraction, subcategory: "Park")
            }
            return Mapping(category: .attraction, subcategory: nil)
        } else if types.contains("movie_theater") {
            return Mapping(category: .entertainment, subcategory: "Movie Theater")
        }
        return Mapping(category: .other, subcategory: nil)
    }
}
