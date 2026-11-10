import Testing
@testable import Circles_iOS

struct AddPlaceCircleCopyTests {
    @Test func cardAsksUntilAChoiceIsMade() {
        #expect(AddPlaceCircleCopy.title(circleName: nil) == "Where should this place live?")
        #expect(AddPlaceCircleCopy.subtitle(circleDetail: nil, remembered: false) == "Choose a circle — the list it will live in")
        #expect(AddPlaceCircleCopy.title(circleName: "Charlotte NC") == "Charlotte NC")
        #expect(AddPlaceCircleCopy.subtitle(circleDetail: "97 places · Connections", remembered: false) == "97 places · Connections")
        #expect(AddPlaceCircleCopy.subtitle(circleDetail: "97 places · Connections", remembered: true) == "97 places · Connections · the one you used last, tap to change")
        #expect(AddPlaceCircleCopy.sectionLabel(remembered: true) == "Circle · the one you used last")
    }

    @Test func saveSaysWhere() {
        #expect(AddPlaceCircleCopy.saveTitle(circleName: nil) == "Choose a circle to save")
        #expect(AddPlaceCircleCopy.saveTitle(circleName: "Charlotte NC") == "Save to Charlotte NC")
        #expect(AddPlaceCircleCopy.saveTitle(circleName: "Entertainment, Recreation, Sightseeing") == "Save to Entertainment, Recrea…")
    }
}
