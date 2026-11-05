import Foundation
import CoreLocation
import Testing
@testable import Circles_iOS

struct DirectionsDestinationTests {
    @Test func googleGetsTheNameAndAddress() throws {
        let d = DirectionsDestination(name: "Fresh Monkee", address: "1500 S Church St, Charlotte, NC 28203",
                                      coordinate: CLLocationCoordinate2D(latitude: 35.21, longitude: -80.86))
        let url = try #require(d.googleMapsURL)
        let daddr = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "daddr" }?.value
        #expect(daddr == "Fresh Monkee, 1500 S Church St, Charlotte, NC 28203")
        #expect(url.absoluteString.hasPrefix("comgooglemaps://"))
    }

    @Test func coordinatesOnlyWithoutAnAddress() throws {
        let d = DirectionsDestination(name: "Pin", address: "", coordinate: CLLocationCoordinate2D(latitude: 35.5, longitude: -80.5))
        let daddr = URLComponents(url: try #require(d.googleMapsURL), resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "daddr" }?.value
        #expect(daddr == "35.5,-80.5")
        #expect(DirectionsDestination(name: "Nowhere", address: "", coordinate: nil).googleMapsURL == nil)
    }

    @Test func ampersandsInNamesDontBreakTheLink() throws {
        let d = DirectionsDestination(name: "Pasta & Provisions", address: "1528 Montford Dr, Charlotte, NC", coordinate: nil)
        let daddr = URLComponents(url: try #require(d.googleMapsURL), resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "daddr" }?.value
        #expect(daddr == "Pasta & Provisions, 1528 Montford Dr, Charlotte, NC")
    }
}
