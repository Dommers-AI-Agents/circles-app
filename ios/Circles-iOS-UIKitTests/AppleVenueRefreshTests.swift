import Testing
import CoreLocation
@testable import Circles_iOS

struct AppleVenueRefreshTests {
    // No Proof's stored pin (W Trade St) and Apple's listing (W Worthington Ave)
    private let oldPin = CLLocationCoordinate2D(latitude: 35.2456339, longitude: -80.8613416)
    private let worthington = CLLocationCoordinate2D(latitude: 35.2133, longitude: -80.8590)
    private let farAway = CLLocationCoordinate2D(latitude: 36.0726, longitude: -79.7920)   // Greensboro

    private func c(_ name: String, _ at: CLLocationCoordinate2D) -> AppleVenueRefresh.Candidate { .init(name: name, coordinate: at) }

    @Test func findsTheBusinessWhereAppleHasItNotUnderTheOldPin() {
        let results = [c("Proof Coffee", oldPin), c("No Proof", worthington)]
        #expect(AppleVenueRefresh.bestMatch(for: "No Proof", near: oldPin, in: results) == 1)
    }

    @Test func fillerWordsAndExtraWordsStillMatch() {
        #expect(AppleVenueRefresh.bestMatch(for: "No Proof", near: oldPin, in: [c("No Proof Bar", worthington)]) == 0)
        #expect(AppleVenueRefresh.bestMatch(for: "No Proof", near: oldPin, in: [c("No Proof CLT", worthington)]) == 0)
        #expect(AppleVenueRefresh.bestMatch(for: "The UPS Store", near: oldPin, in: [c("UPS Store", worthington)]) == 0)
    }

    @Test func aDifferentBusinessOrOneTooFarIsNotIt() {
        #expect(AppleVenueRefresh.bestMatch(for: "No Proof", near: oldPin, in: [c("Proof Coffee", worthington)]) == nil)
        #expect(AppleVenueRefresh.bestMatch(for: "No Proof", near: oldPin, in: [c("No Proof", farAway)]) == nil)
    }

    @Test func nearestOfSeveralBranches() {
        let near = CLLocationCoordinate2D(latitude: 35.2460, longitude: -80.8610)
        let results = [c("Starbucks", worthington), c("Starbucks", near)]
        #expect(AppleVenueRefresh.bestMatch(for: "Starbucks", near: oldPin, in: results) == 1)
    }
}
