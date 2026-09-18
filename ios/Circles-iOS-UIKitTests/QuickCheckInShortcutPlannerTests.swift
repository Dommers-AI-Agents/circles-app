import Testing
import Foundation
import CoreLocation
@testable import Circles_iOS

/// Which saved places become "Check in at <name>" rows on the app icon's
/// long-press menu, and how a tapped row turns back into a pending link.
struct QuickCheckInShortcutPlannerTests {
    private let here = CLLocation(latitude: 35.2271, longitude: -80.8431)

    /// A place `meters` due north of `here`. 1° latitude ≈ 111,320 m.
    private func place(_ id: String, meters: Double, name: String? = nil, located: Bool = true) -> Place {
        let location = located
            ? GeoLocation(type: "Point", coordinates: [here.coordinate.longitude,
                                                       here.coordinate.latitude + meters / 111_320])
            : nil
        return Place(id: id, name: name ?? id, description: nil, address: "", location: location, website: nil,
                     phone: nil, googlePlaceId: nil, photos: nil, videos: nil, category: .restaurant,
                     customCategoryId: nil, subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil,
                     privateNotes: nil, publicNotes: nil, tags: nil, reviews: nil, openingHours: nil,
                     priceLevel: nil, likes: nil, likesCount: nil, commentsCount: nil, circleId: "c",
                     addedBy: "u", addedByUser: nil, privacy: .public, createdAt: Date(), updatedAt: Date())
    }

    @Test func nearestFirstWithinRadiusCappedAtLimit() {
        let places = [
            place("far", meters: 1_400),
            place("near", meters: 40),
            place("mid", meters: 300),
            place("out", meters: 5_000),
            place("mid2", meters: 900),
        ]
        let plan = QuickCheckInShortcutPlanner.plan(places: places, around: here, limit: 3)
        #expect(plan.map(\.placeId) == ["near", "mid", "mid2"])
        #expect(plan.first?.placeName == "near")
    }

    @Test func byDefaultOnlyTheNearestRowIsPlanned() {
        // Three static items (Check In, Add a Place, Send a Postcard) fill the
        // rest of the four-item menu
        let places = [place("far", meters: 1_400), place("near", meters: 40), place("mid", meters: 300)]
        #expect(QuickCheckInShortcutPlanner.defaultLimit == 1)
        #expect(QuickCheckInShortcutPlanner.plan(places: places, around: here).map(\.placeId) == ["near"])
    }

    @Test func noLocationMeansNoRows() {
        #expect(QuickCheckInShortcutPlanner.plan(places: [place("a", meters: 10)], around: nil).isEmpty)
        #expect(QuickCheckInShortcutPlanner.plan(places: [place("a", meters: 10)], around: here, limit: 0).isEmpty)
    }

    @Test func coincidentSavesCollapseToOneRow() {
        let places = [place("a", meters: 50, name: "Cafe"), place("b", meters: 60, name: "Cafe")]
        let plan = QuickCheckInShortcutPlanner.plan(places: places, around: here)
        #expect(plan.map(\.placeId) == ["a"])
    }

    @Test func placesWithoutCoordinatesOrNamesAreSkipped() {
        let unnamed = place("blank", meters: 20, name: "  ")
        let unlocated = place("nowhere", meters: 20, located: false)
        let plan = QuickCheckInShortcutPlanner.plan(places: [unnamed, unlocated, place("ok", meters: 100)], around: here)
        #expect(plan.map(\.placeId) == ["ok"])
    }

    @Test func tappedItemsBecomePendingLinks() {
        let staticType = QuickCheckInShortcutPlanner.checkInType
        let placeType = QuickCheckInShortcutPlanner.checkInAtPlaceType
        #expect(QuickCheckInShortcutPlanner.pendingLink(forShortcutType: staticType, userInfo: nil) == "check-in")
        #expect(QuickCheckInShortcutPlanner.pendingLink(forShortcutType: QuickCheckInShortcutPlanner.addPlaceType, userInfo: nil) == "add-place")
        #expect(QuickCheckInShortcutPlanner.pendingLink(forShortcutType: QuickCheckInShortcutPlanner.postcardType, userInfo: nil) == "widget:postcard")
        #expect(QuickCheckInShortcutPlanner.pendingLink(forShortcutType: placeType, userInfo: ["placeId": "abc"]) == "check-in:abc")
        #expect(QuickCheckInShortcutPlanner.pendingLink(forShortcutType: placeType, userInfo: ["placeId": " "]) == nil)
        #expect(QuickCheckInShortcutPlanner.pendingLink(forShortcutType: placeType, userInfo: nil) == nil)
        #expect(QuickCheckInShortcutPlanner.pendingLink(forShortcutType: "com.other.thing", userInfo: nil) == nil)
    }
}
