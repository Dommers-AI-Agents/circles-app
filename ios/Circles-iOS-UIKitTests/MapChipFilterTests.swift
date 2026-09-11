import Testing
import Foundation
@testable import Circles_iOS

/// The full-screen map's content filters: origin sub-filter, category
/// group, region chip, and search text.
struct MapChipFilterTests {
    private func place(_ id: String, category: PlaceCategory = .restaurant, importSource: String? = nil) -> Place {
        var place = Place(id: id, name: id, description: nil, address: "", location: nil, website: nil, phone: nil,
                          googlePlaceId: nil, photos: nil, videos: nil, category: category, customCategoryId: nil,
                          subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
                          publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
                          likesCount: nil, commentsCount: nil, circleId: nil, addedBy: "me", addedByUser: nil,
                          privacy: .public, createdAt: Date(), updatedAt: Date())
        place.importSource = importSource
        return place
    }
    private func ids(_ places: [Place]) -> [String] { places.map { $0.id } }

    private var sample: [Place] {
        [
            place("diner"),
            place("inn", category: .hotel),
            place("imported-diner", importSource: "google_maps"),
            place("imported-inn", category: .hotel, importSource: "mapstr")
        ]
    }

    @Test func noSelectionsPassEverythingThrough() {
        #expect(ids(MapChipFilter.apply(sample, context: MapChipFilter.Context())) == ids(sample))
    }

    @Test func originInAppMeansNoImportSource() {
        #expect(ids(MapChipFilter.applyOrigin(sample, origin: "in_app")) == ["diner", "inn"])
        #expect(ids(MapChipFilter.applyOrigin(sample, origin: "google_maps")) == ["imported-diner"])
        #expect(ids(MapChipFilter.applyOrigin(sample, origin: nil)) == ids(sample))
    }

    @Test func categoryGroupFiltersByRawCategory() {
        let hotels = PlaceCategoryGroup.group(for: PlaceCategory.hotel.rawValue)
        let food = PlaceCategoryGroup.group(for: PlaceCategory.restaurant.rawValue)
        #expect(hotels != food)
        var context = MapChipFilter.Context()
        context.group = hotels
        #expect(ids(MapChipFilter.apply(sample, context: context)) == ["inn", "imported-inn"])
    }

    @Test func regionChipKeepsOnlyItsPlacesAndIgnoresUnknownIds() {
        let region = RegionGroup(id: "state:NJ", title: "New Jersey", count: 1, placeIds: ["inn"], centroid: nil)
        var context = MapChipFilter.Context()
        context.regionGroups = [region]
        context.regionId = "state:NJ"
        #expect(ids(MapChipFilter.apply(sample, context: context)) == ["inn"])
        context.regionId = "state:XX"
        #expect(ids(MapChipFilter.apply(sample, context: context)) == ids(sample))
    }

    @Test func filtersStackOriginThenGroupThenRegion() {
        let region = RegionGroup(id: "r", title: "R", count: 2, placeIds: ["inn", "imported-inn"], centroid: nil)
        var context = MapChipFilter.Context()
        context.importOrigin = "mapstr"
        context.group = PlaceCategoryGroup.group(for: PlaceCategory.hotel.rawValue)
        context.regionGroups = [region]
        context.regionId = "r"
        #expect(ids(MapChipFilter.apply(sample, context: context)) == ["imported-inn"])
    }

    @Test func searchNormalizesAndMatchesNames() {
        #expect(MapChipFilter.normalizedQuery("  ") == nil)
        #expect(MapChipFilter.normalizedQuery(nil) == nil)
        #expect(MapChipFilter.normalizedQuery(" inn ") == "inn")
        #expect(ids(MapChipFilter.applySearch(sample, query: "inn")) == ["inn", "imported-inn"])
        #expect(ids(MapChipFilter.applySearch(sample, query: nil)) == ids(sample))
    }

    @Test func originTitles() {
        #expect(MapChipFilter.originTitle("in_app") == "FavCircles")
        #expect(MapChipFilter.originTitle("google_maps") == "Google Places")
        #expect(MapChipFilter.originTitle("mapstr") == "Mapstr")
        #expect(MapChipFilter.originTitle("swarm") == "Swarm")
        #expect(MapChipFilter.originTitle("foursquare") == "Foursquare")
    }
}
