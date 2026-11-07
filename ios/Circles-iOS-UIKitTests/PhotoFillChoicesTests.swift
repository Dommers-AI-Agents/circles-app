import Testing
@testable import Circles_iOS

struct PhotoFillChoicesTests {
    @Test func nothingNearbyPinsTheSpot() {
        #expect(PhotoFillChoices.decide(candidateCount: 0) == .pin)
    }

    @Test func oneLikelyPlaceFillsIt() {
        #expect(PhotoFillChoices.decide(candidateCount: 1) == .fill(index: 0))
    }

    @Test func severalAskInsteadOfGuessing() {
        // Golden Cow Creamery and LDI Reproprinting share a block
        #expect(PhotoFillChoices.decide(candidateCount: 2) == .ask(count: 2))
        #expect(PhotoFillChoices.decide(candidateCount: 9) == .ask(count: 5))
    }

    @Test func rowSaysWhatKindOfPlace() {
        #expect(PhotoFillChoices.rowTitle(name: "Golden Cow Creamery", kind: "Ice Cream") == "Golden Cow Creamery · Ice Cream")
        #expect(PhotoFillChoices.rowTitle(name: "Kingston Park", kind: "Park") == "Kingston Park")
        #expect(PhotoFillChoices.rowTitle(name: "LDI Reproprinting Center", kind: "Other") == "LDI Reproprinting Center")
        #expect(PhotoFillChoices.rowTitle(name: "Ilios", kind: " ") == "Ilios")
    }
}
