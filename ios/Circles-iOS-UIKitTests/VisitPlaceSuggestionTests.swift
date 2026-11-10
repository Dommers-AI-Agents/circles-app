import Testing
import Foundation
@testable import Circles_iOS

/// Visits are named for the business, not the street address.
struct VisitPlaceSuggestionTests {
    private func c(_ name: String, _ distance: Double) -> VisitPlaceSuggestion.Candidate {
        .init(name: name, address: "1120 S Tryon St, Charlotte", category: "restaurant", distance: distance)
    }

    @Test func addressesArePlaceholders() {
        #expect(VisitPlaceSuggestion.looksLikeAddress("1120 S Tryon St"))
        #expect(VisitPlaceSuggestion.looksLikeAddress("400, E Morehead St"))
        #expect(VisitPlaceSuggestion.looksLikeAddress("Unknown Place"))
        #expect(!VisitPlaceSuggestion.looksLikeAddress("Culinary Dropout"))
        #expect(!VisitPlaceSuggestion.looksLikeAddress("7th Street Public Market"))
    }

    @Test func theNearestCloseBusinessNamesTheVisit() {
        #expect(VisitPlaceSuggestion.autoName(from: [c("Sixty Vines", 45), c("Culinary Dropout", 20)])?.name == "Culinary Dropout")
        #expect(VisitPlaceSuggestion.autoName(from: [c("Far Away Cafe", 90)]) == nil)
        #expect(VisitPlaceSuggestion.autoName(from: []) == nil)
    }

    @Test func bareStreetsAndAddressPiecesArePlaceholders() {
        let address = "1120 S Tryon St, Charlotte, NC, 28203"
        #expect(VisitPlaceSuggestion.looksLikeAddress("S Tryon St"))
        #expect(VisitPlaceSuggestion.looksLikeAddress("Morehead Street"))
        #expect(VisitPlaceSuggestion.looksLikeAddress("Charlotte", address: address))
        #expect(VisitPlaceSuggestion.looksLikeAddress("S Tryon St", address: address))
        #expect(!VisitPlaceSuggestion.looksLikeAddress("Charlotte", address: nil))
        #expect(!VisitPlaceSuggestion.looksLikeAddress("Optimist Hall", address: address))
        #expect(!VisitPlaceSuggestion.looksLikeAddress("Main Street Pizza", address: address))
    }

    @Test func aRoughFixReachesFarther() {
        #expect(VisitPlaceSuggestion.reach(accuracy: nil) == 60)
        #expect(VisitPlaceSuggestion.reach(accuracy: 20) == 60)
        #expect(VisitPlaceSuggestion.reach(accuracy: 110) == 110)
        #expect(VisitPlaceSuggestion.reach(accuracy: 900) == 150)
        #expect(VisitPlaceSuggestion.autoName(from: [c("Far Away Cafe", 90)], accuracy: 120)?.name == "Far Away Cafe")
        #expect(VisitPlaceSuggestion.autoName(from: [c("Too Far Cafe", 160)], accuracy: 900) == nil)
    }

    @Test func aTossUpIsLeftForThePerson() {
        // Two about as close, neither very close: don't guess
        #expect(VisitPlaceSuggestion.autoName(from: [c("Sixty Vines", 70), c("Culinary Dropout", 80)], accuracy: 120) == nil)
        // Clearly nearer wins
        #expect(VisitPlaceSuggestion.autoName(from: [c("Sixty Vines", 40), c("Culinary Dropout", 100)], accuracy: 120)?.name == "Sixty Vines")
        // Very close always wins
        #expect(VisitPlaceSuggestion.autoName(from: [c("Sixty Vines", 25), c("Culinary Dropout", 30)])?.name == "Sixty Vines")
        // The same business twice is no toss-up
        #expect(VisitPlaceSuggestion.autoName(from: [c("Starbucks", 50), c("starbucks", 55)])?.name == "Starbucks")
    }

    @Test func unnamedVisitsReadNearTheStreet() {
        var visit = PlaceVisit(id: "v", userId: "u", placeName: "1120 S Tryon St", placeAddress: "1120 S Tryon St, Charlotte, NC",
                               latitude: 35.2, longitude: -80.8, category: nil, visitedAt: Date(), duration: 30,
                               autoDetected: true, reviewed: false, dismissed: false)
        #expect(VisitPlaceSuggestion.needsName(visit))
        #expect(VisitPlaceSuggestion.nearTitle(visit) == "Near 1120 S Tryon St")
        visit.dismissed = true
        #expect(!VisitPlaceSuggestion.needsName(visit))
        visit.dismissed = false
        visit.placeName = "Optimist Hall"
        #expect(!VisitPlaceSuggestion.needsName(visit))
    }

    @Test func choicesAreNearestFirstOncePerName() {
        let list = VisitPlaceSuggestion.choices(from: [c("B", 50), c("A", 10), c("a", 30), c("Gone", 500)])
        #expect(list.map(\.name) == ["A", "B"])
    }
}
