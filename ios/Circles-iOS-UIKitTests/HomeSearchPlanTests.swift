import Foundation
import Testing
@testable import Circles_iOS

/// The rules that decide what the home search dropdown shows.
struct HomeSearchPlanTests {
    @Test func aMatchedPlaceAlwaysGetsARowToTap() {
        // The Nickyo's case: one local match. It filtered the map correctly and
        // had no row anywhere, which is the bug this type exists to prevent.
        let plan = HomeSearchPlan.make(mode: .places, matchedPlaces: 1, suggestedPlaces: 0, people: 1)
        #expect(plan.placeRows == 1)
        #expect(plan.hasRows)
        #expect(plan.filtersMap)
    }

    @Test func theListStaysShortAndSaysWhatItLeftOut() {
        let plan = HomeSearchPlan.make(mode: .places, matchedPlaces: 15, suggestedPlaces: 0, people: 0)
        #expect(plan.placeRows == 3)
        #expect(plan.placeOverflow == 12)
        #expect(plan.placesHeader == "PLACES · 12 more on the map")

        let exact = HomeSearchPlan.make(mode: .places, matchedPlaces: 3, suggestedPlaces: 0, people: 0)
        #expect(exact.placeOverflow == 0)
        #expect(exact.placesHeader == "PLACES")
    }

    @Test func nearbyVenuesLeadWhenNothingMatchedAndTrailWhenSomethingDid() {
        let nothingLocal = HomeSearchPlan.make(mode: .places, matchedPlaces: 0, suggestedPlaces: 9, people: 0)
        #expect(nothingLocal.suggestedRows == 6)   // capped
        #expect(nothingLocal.suggestedHeader == "SUGGESTED NEARBY")

        // Your own matches lead; a few more nearby follow ("Deli" should show
        // the other delis, not only the one you saved) — Wes, 2026-09-22.
        let somethingLocal = HomeSearchPlan.make(mode: .places, matchedPlaces: 2, suggestedPlaces: 9, people: 0)
        #expect(somethingLocal.suggestedRows == 3)
        #expect(somethingLocal.placeRows == 2)
        #expect(somethingLocal.suggestedHeader == "MORE NEARBY")
        #expect(HomeSearchPlan.make(mode: .places, matchedPlaces: 2, suggestedPlaces: 0, people: 0).suggestedRows == 0)
    }

    @Test func peopleModeLeavesTheMapAlone() {
        let plan = HomeSearchPlan.make(mode: .people, matchedPlaces: 40, suggestedPlaces: 9, people: 2)
        #expect(!plan.filtersMap)
        #expect(plan.peopleRows == 2)
        #expect(plan.placeRows == 0)
        #expect(plan.suggestedRows == 0)
    }

    @Test func eachModeShowsOnlyItsOwnKind() {
        let places = HomeSearchPlan.make(mode: .places, matchedPlaces: 1, suggestedPlaces: 0, people: 5)
        #expect(places.peopleRows == 0)
        let people = HomeSearchPlan.make(mode: .people, matchedPlaces: 0, suggestedPlaces: 0, people: 9)
        #expect(people.peopleRows == 6)   // capped
    }

    @Test func nothingToShowIsNotAnEmptyDropdown() {
        let plan = HomeSearchPlan.make(mode: .places, matchedPlaces: 0, suggestedPlaces: 0, people: 3)
        #expect(!plan.hasRows)
    }

    @Test func negativeCountsCannotProduceNegativeRows() {
        let plan = HomeSearchPlan.make(mode: .places, matchedPlaces: -1, suggestedPlaces: -1, people: -1)
        #expect(plan.placeRows == 0)
        #expect(plan.placeOverflow == 0)
        #expect(!plan.hasRows)
    }
}
