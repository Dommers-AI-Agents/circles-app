import Foundation
import Testing
@testable import Circles_iOS

/// The rules that decide what the home search results sheet shows. One sheet
/// for everything since 2026-10-29 (Wes): Places | People | Nearby, counted.
struct HomeSearchPlanTests {
    @Test func aMatchedPlaceAlwaysGetsARowToTap() {
        // The Nickyo's case: one local match. It filtered the map correctly and
        // had no row anywhere, which is the bug this type exists to prevent.
        let plan = HomeSearchPlan.make(matchedPlaces: 1, suggestedPlaces: 0, people: 1)
        #expect(plan.placeRows == 1)
        #expect(plan.peopleRows == 1)
        #expect(plan.hasRows)
        #expect(plan.filtersMap)
    }

    @Test func everyKindShowsTogether() {
        let plan = HomeSearchPlan.make(matchedPlaces: 26, suggestedPlaces: 9, people: 2)
        #expect(plan.placeRows == 26)
        #expect(plan.peopleRows == 2)
        #expect(plan.suggestedRows == 3)
        #expect(plan.handleTitle == "Places 26 | People 2 | Nearby 3")
        #expect(plan.placesHeader == "PLACES (26)")
        #expect(plan.peopleHeader == "PEOPLE (2)")
        #expect(plan.suggestedHeader == "NEARBY (3)")
    }

    @Test func theHandleNamesOnlyWhatIsThere() {
        #expect(HomeSearchPlan.make(matchedPlaces: 1, suggestedPlaces: 3, people: 0).handleTitle == "Places 1 | Nearby 3")
        #expect(HomeSearchPlan.make(matchedPlaces: 0, suggestedPlaces: 9, people: 0).handleTitle == "Nearby 6")
        #expect(HomeSearchPlan.make(matchedPlaces: 0, suggestedPlaces: 0, people: 1).handleTitle == "People 1")
        #expect(HomeSearchPlan.make(matchedPlaces: 2, suggestedPlaces: 0, people: 0, widgets: 1).handleTitle == "Places 2 | Widgets 1")
        #expect(HomeSearchPlan.make(matchedPlaces: 0, suggestedPlaces: 0, people: 0).handleTitle == "No matches")
    }

    @Test func nearbyVenuesLeadWhenNothingMatchedAndTrailWhenSomethingDid() {
        #expect(HomeSearchPlan.make(matchedPlaces: 0, suggestedPlaces: 9, people: 0).suggestedRows == 6)   // capped
        // Your own matches lead; a few more nearby follow ("Deli" should show
        // the other delis, not only the one you saved) — Wes, 2026-09-22.
        let somethingLocal = HomeSearchPlan.make(matchedPlaces: 2, suggestedPlaces: 9, people: 0)
        #expect(somethingLocal.suggestedRows == 3)
        #expect(HomeSearchPlan.make(matchedPlaces: 2, suggestedPlaces: 0, people: 0).suggestedRows == 0)
    }

    @Test func aPersonOnlyQueryLeavesTheMapAlone() {
        // "Nick" naming only a person must not empty the map
        let plan = HomeSearchPlan.make(matchedPlaces: 0, suggestedPlaces: 4, people: 2)
        #expect(!plan.filtersMap)
        #expect(plan.hasRows)
    }

    @Test func peopleAndWidgetsAreCapped() {
        let plan = HomeSearchPlan.make(matchedPlaces: 0, suggestedPlaces: 0, people: 9, widgets: 5)
        #expect(plan.peopleRows == HomeSearchPlan.maxPeopleRows)
        #expect(plan.widgetRows == HomeSearchPlan.maxWidgetRows)
    }

    @Test func nothingToShowIsNotAnEmptyDropdown() {
        #expect(!HomeSearchPlan.make(matchedPlaces: 0, suggestedPlaces: 0, people: 0).hasRows)
    }

    @Test func negativeCountsCannotProduceNegativeRows() {
        let plan = HomeSearchPlan.make(matchedPlaces: -1, suggestedPlaces: -1, people: -1)
        #expect(plan.placeRows == 0)
        #expect(plan.peopleRows == 0)
        #expect(!plan.hasRows)
    }
}
