import Testing
@testable import Circles_iOS

/// The place page's "Good to know" line and closed warning (2026-10-29).
struct PlaceGoodToKnowTests {

    @Test func frenchysReadsNaturally() {
        let f = PlaceGoodToKnow.Facts(serves: PlaceServes(beer: true, wine: true), dineIn: true, takeout: true,
                                      wheelchairAccessibleEntrance: true)
        #expect(PlaceGoodToKnow.line(f) == "Wine & beer \u{00B7} Dine-in \u{00B7} Takeout \u{00B7} Wheelchair-accessible entrance")
    }

    @Test func mealsJoinLikeASentence() {
        #expect(PlaceGoodToKnow.naturalList(["Brunch", "Dinner"]) == "Brunch & dinner")
        #expect(PlaceGoodToKnow.naturalList(["Breakfast", "Lunch", "Dinner"]) == "Breakfast, lunch & dinner")
        #expect(PlaceGoodToKnow.naturalList(["Lunch"]) == "Lunch")
        #expect(PlaceGoodToKnow.naturalList([]) == nil)
    }

    @Test func onlyWhatIsKnownToBeTrueIsListed() {
        let f = PlaceGoodToKnow.Facts(serves: PlaceServes(breakfast: false, lunch: nil, dinner: true, vegetarian: true),
                                      dineIn: false, delivery: true, reservable: true)
        #expect(PlaceGoodToKnow.items(f) == ["Dinner", "Vegetarian options", "Delivery", "Takes reservations"])
        #expect(PlaceGoodToKnow.line(PlaceGoodToKnow.Facts()) == nil)
    }

    @Test func closedWarnings() {
        #expect(PlaceGoodToKnow.closedNotice("CLOSED_PERMANENTLY") == "Permanently closed, according to Google")
        #expect(PlaceGoodToKnow.closedNotice("CLOSED_TEMPORARILY") == "Temporarily closed, according to Google")
        #expect(PlaceGoodToKnow.closedNotice("OPERATIONAL") == nil)
        #expect(PlaceGoodToKnow.closedNotice(nil) == nil)
    }
}
