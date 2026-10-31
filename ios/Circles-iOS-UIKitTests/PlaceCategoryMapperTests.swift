import Testing
@testable import Circles_iOS

/// Google Places types → the add-place form's category and subcategory.
struct PlaceCategoryMapperTests {
    private func map(_ types: [String]) -> PlaceCategoryMapper.Mapping {
        PlaceCategoryMapper.mapping(forGoogleTypes: types)
    }

    @Test func restaurantsWinOverEverythingElse() {
        #expect(map(["restaurant", "cafe", "bar"]) == .init(category: .restaurant, subcategory: nil))
        #expect(map(["food", "meal_takeaway"]) == .init(category: .restaurant, subcategory: "Fast Food"))
        // A bakery is a Café, as the server files it, even when also tagged a restaurant
        #expect(map(["restaurant", "bakery"]) == .init(category: .cafe, subcategory: "Bakery"))
        #expect(map(["bakery"]) == .init(category: .cafe, subcategory: "Bakery"))
        #expect(map(["restaurant", "meal_delivery"]) == .init(category: .restaurant, subcategory: "Fast Food"))
    }

    @Test func subcategoriesComeFromTheMoreSpecificType() {
        #expect(map(["cafe", "coffee_shop"]) == .init(category: .cafe, subcategory: "Coffee Shop"))
        #expect(map(["cafe"]) == .init(category: .cafe, subcategory: nil))
        #expect(map(["night_club"]) == .init(category: .bar, subcategory: "Nightclub"))
        #expect(map(["store", "clothing_store"]) == .init(category: .retail, subcategory: "Clothing Store"))
        #expect(map(["shopping_mall"]) == .init(category: .retail, subcategory: nil))
        #expect(map(["spa"]) == .init(category: .service, subcategory: "Spa"))
        #expect(map(["hair_care", "beauty_salon"]) == .init(category: .service, subcategory: "Beauty Salon"))
        #expect(map(["health"]) == .init(category: .fitness, subcategory: nil))
        #expect(map(["pharmacy"]) == .init(category: .healthcare, subcategory: "Pharmacy"))
        #expect(map(["hospital", "doctor"]) == .init(category: .healthcare, subcategory: "Doctor"))
        #expect(map(["park"]) == .init(category: .attraction, subcategory: "Park"))
        #expect(map(["tourist_attraction"]) == .init(category: .attraction, subcategory: nil))
        #expect(map(["movie_theater"]) == .init(category: .entertainment, subcategory: "Movie Theater"))
    }

    @Test func unknownTypesFallBackToOther() {
        #expect(map(["establishment", "point_of_interest"]) == .init(category: .other, subcategory: nil))
        #expect(map([]) == .init(category: .other, subcategory: nil))
    }
}
