import Testing
import Foundation
@testable import Circles_iOS

/// The map's people dropdown is ranked by places in the current view
/// (Wes, 2026-11-07).
struct MapPeopleInViewTests {
    private func place(_ id: String, addedBy: String, circle: String? = nil) -> Place {
        Place(id: id, name: id, description: nil, address: "", location: nil, website: nil, phone: nil,
              googlePlaceId: nil, photos: nil, videos: nil, category: .restaurant, customCategoryId: nil,
              subcategory: nil, rating: nil, userRatingsTotal: nil, notes: nil, privateNotes: nil,
              publicNotes: nil, tags: nil, reviews: nil, openingHours: nil, priceLevel: nil, likes: nil,
              likesCount: nil, commentsCount: nil, circleId: circle, addedBy: addedBy, addedByUser: nil,
              privacy: .public, createdAt: Date(), updatedAt: Date())
    }

    @Test func countsOnlyPlacesInViewPerPerson() {
        let places = [place("a1", addedBy: "ann"), place("a2", addedBy: "ann"), place("a3", addedBy: "ann"),
                      place("b1", addedBy: "bill"), place("far", addedBy: "bill")]
        let counts = MapPeopleInView.counts(places, author: { $0.addedBy }, isInView: { $0.id != "far" })
        #expect(counts == ["ann": 3, "bill": 1])
    }

    @Test func aPlaceLoadedTwiceCountsOnce() {
        let places = [place("a1", addedBy: "ann"), place("a1", addedBy: "ann")]
        #expect(MapPeopleInView.counts(places, author: { $0.addedBy }, isInView: { _ in true }) == ["ann": 1])
    }

    @Test func countsByTheCircleOwnerLikeTheHomeMap() {
        // Saved under a legacy account id, in Ann's circle: it's Ann's pin
        let places = [place("x", addedBy: "ann-legacy", circle: "c1")]
        let counts = MapPeopleInView.counts(places,
                                            author: { HomePlaceFilter.author(of: $0, networkCircleOwners: ["c1": "ann"]) },
                                            isInView: { _ in true })
        #expect(counts == ["ann": 1])
    }

    @Test func mostPlacesInViewFirstThenTheRestInRowOrder() {
        let people = ["brittany", "bill", "chelsea", "dylon", "renee"]
        let ordered = MapPeopleInView.ordered(people, id: { $0 }, counts: ["dylon": 2, "renee": 9, "bill": 2])
        // Renee (9), then Bill and Dylon tied at 2 in row order, then the rest as they were
        #expect(ordered == ["renee", "bill", "dylon", "brittany", "chelsea"])
    }

    @Test func noCountsKeepsTheRowOrder() {
        let people = ["brittany", "bill", "chelsea"]
        #expect(MapPeopleInView.ordered(people, id: { $0 }, counts: [:]) == people)
    }

    @Test func subtitleSaysHowManyAreHere() {
        #expect(MapPeopleInView.subtitle(count: 0) == nil)
        #expect(MapPeopleInView.subtitle(count: 1) == "1 place here")
        #expect(MapPeopleInView.subtitle(count: 12) == "12 places here")
    }
}
