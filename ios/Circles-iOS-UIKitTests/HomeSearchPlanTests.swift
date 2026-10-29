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
        // Counts are of everything found; All shows three nearby + "Show all 9"
        #expect(plan.handleTitle == "Places 26 | People 2 | Nearby 9")
        #expect(plan.placesHeader == "PLACES (26)")
        #expect(plan.peopleHeader == "PEOPLE (2)")
        #expect(plan.suggestedHeader == "NEARBY (9)")
        #expect(plan.moreNearby)
        #expect(plan.suggestedSectionRows == 4)
        #expect(!plan.morePeople)
    }

    @Test func theHandleNamesOnlyWhatIsThere() {
        #expect(HomeSearchPlan.make(matchedPlaces: 1, suggestedPlaces: 3, people: 0).handleTitle == "Places 1 | Nearby 3")
        #expect(HomeSearchPlan.make(matchedPlaces: 0, suggestedPlaces: 9, people: 0).handleTitle == "Nearby 9")
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

    @Test func chipsAppearOnlyWhenThereIsAChoice() {
        let mixed = HomeSearchPlan.make(matchedPlaces: 4, suggestedPlaces: 8, people: 2)
        #expect(mixed.scopeChips == [.all, .places, .people, .nearby])
        #expect(mixed.chipTitle(.people) == "People 2")
        #expect(HomeSearchPlan.make(matchedPlaces: 4, suggestedPlaces: 0, people: 0).scopeChips.isEmpty)
        #expect(HomeSearchPlan.idle(recent: 3).scopeChips.isEmpty)
    }

    @Test func aChipNarrowsTheSheetToItsKind() {
        let people = HomeSearchPlan.make(matchedPlaces: 4, suggestedPlaces: 8, people: 12, scope: .people)
        #expect(people.scope == .people)
        #expect(people.peopleRows == 12)        // every one, not the All cap of 6
        #expect(people.placeRows == 0 && people.suggestedRows == 0)
        #expect(!people.morePeople)
        #expect(people.scopeChips == [.all, .places, .people, .nearby])   // still there to switch back
        let nearby = HomeSearchPlan.make(matchedPlaces: 4, suggestedPlaces: 8, people: 0, scope: .nearby)
        #expect(nearby.suggestedRows == 8)
        // The pins still follow the places that matched
        #expect(people.filtersMap)
    }

    @Test func aChipWhoseKindEmptiedFallsBackToAll() {
        let plan = HomeSearchPlan.make(matchedPlaces: 3, suggestedPlaces: 2, people: 0, scope: .people)
        #expect(plan.scope == .all)
        #expect(plan.placeRows == 3)
    }

    @Test func allCutsPeopleShortWithAShowAllRow() {
        let plan = HomeSearchPlan.make(matchedPlaces: 1, suggestedPlaces: 0, people: 12)
        #expect(plan.peopleRows == HomeSearchPlan.maxPeopleRows)
        #expect(plan.morePeople)
        #expect(plan.peopleSectionRows == HomeSearchPlan.maxPeopleRows + 1)
    }
}
