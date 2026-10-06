import Testing
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

    @Test func choicesAreNearestFirstOncePerName() {
        let list = VisitPlaceSuggestion.choices(from: [c("B", 50), c("A", 10), c("a", 30), c("Gone", 500)])
        #expect(list.map(\.name) == ["A", "B"])
    }
}
