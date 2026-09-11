import Testing
import Foundation
@testable import Circles_iOS

/// Current chip semantics on the circle screen, captured before the logic
/// moved off the controller.
struct CirclePlaceFilterTests {
    private func place(_ id: String, category: PlaceCategory = .restaurant, tags: [String]? = nil) -> Place {
        Place(id: id, name: id, description: nil, address: "", location: nil, website: nil, phone: nil,
              googlePlaceId: nil, photos: nil, videos: nil, category: category, customCategoryId: nil,
              subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
              publicNotes: nil, tags: tags, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
              likesCount: nil, commentsCount: nil, circleId: "c", addedBy: "u", addedByUser: nil,
              privacy: .public, createdAt: Date(), updatedAt: Date())
    }

    @Test func chipsAreMostCommonFirstWithAlphabeticalTieBreak() {
        let places = [
            place("a", tags: ["Brunch", "patio"]),
            place("b", tags: ["brunch", "Cheap"]),
            place("c", tags: ["cheap", "BRUNCH", "brunch"]) // duplicate within a place counts once
        ]
        #expect(CirclePlaceFilter.tagChips(for: places) == ["Brunch", "Cheap", "patio"])
    }

    @Test func chipsKeepFirstSeenSpellingTrimWhitespaceAndCapAtLimit() {
        let places = [
            place("a", tags: ["  Date Night ", "", "   "]),
            place("b", tags: ["date night"])
        ]
        #expect(CirclePlaceFilter.tagChips(for: places) == ["  Date Night "])

        let many = (0..<20).map { i in place("p\(i)", tags: ["t\(String(format: "%02d", i))"]) }
        #expect(CirclePlaceFilter.tagChips(for: many).count == 12)
        #expect(CirclePlaceFilter.tagChips(for: many, limit: 3) == ["t00", "t01", "t02"])
        #expect(CirclePlaceFilter.tagChips(for: [place("x")]).isEmpty)
    }

    @Test func selectionResetsOnlyWhenItsChipDisappears() {
        #expect(CirclePlaceFilter.selectionAfterRebuild(selected: "brunch", chips: ["Brunch"]) == "brunch")
        #expect(CirclePlaceFilter.selectionAfterRebuild(selected: "patio", chips: ["Brunch"]) == nil)
        #expect(CirclePlaceFilter.selectionAfterRebuild(selected: nil, chips: []) == nil)
    }

    @Test func categoryOptionsAreDistinctAndOrderedByDisplayName() {
        let places = [place("a", category: .retail), place("b", category: .restaurant), place("c", category: .retail)]
        let options = CirclePlaceFilter.categoryOptions(for: places)
        #expect(options.count == 2)
        #expect(options == options.sorted { $0.displayName < $1.displayName })
        #expect(Set(options) == Set<PlaceCategory>([.retail, .restaurant]))
    }

    @Test func applyMatchesCategoryExactlyAndTagCaseInsensitively() {
        let places = [
            place("a", category: .restaurant, tags: ["Brunch"]),
            place("b", category: .cafe, tags: ["brunch"]),
            place("c", category: .restaurant, tags: nil)
        ]
        #expect(CirclePlaceFilter.apply(places, category: nil, tag: nil).map { $0.id } == ["a", "b", "c"])
        #expect(CirclePlaceFilter.apply(places, category: .restaurant, tag: nil).map { $0.id } == ["a", "c"])
        #expect(CirclePlaceFilter.apply(places, category: nil, tag: "BRUNCH").map { $0.id } == ["a", "b"])
        #expect(CirclePlaceFilter.apply(places, category: .cafe, tag: "brunch").map { $0.id } == ["b"])
        #expect(CirclePlaceFilter.apply(places, category: .restaurant, tag: "patio").isEmpty)
    }
}
