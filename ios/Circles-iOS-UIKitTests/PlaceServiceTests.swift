import CoreLocation
import Foundation
import Testing
@testable import Circles_iOS

/// PlaceService against a fake APIClient: the endpoints it builds and how it
/// reads list answers.
struct PlaceServiceTests {
    @Test func networkSearchEncodesTheQueryAndOrigin() {
        let api = FakeAPIClient()
        api.responseJSON = #"{"success": true, "places": []}"#
        let service = PlaceService(api: api)

        service.searchNetworkPlaces(query: "fish & chips",
                                    near: CLLocation(latitude: 35.227087, longitude: -80.843127),
                                    limit: 20) { _ in }

        #expect(api.calls.count == 1)
        #expect(api.calls.first?.endpoint ==
                "network/places/search?limit=20&query=fish%20%26%20chips&lat=35.22709&lng=-80.84313")
        #expect(api.calls.first?.method == .get)
        #expect(api.calls.first?.requiresAuth == true)
    }

    @Test func networkSearchWithoutAnOriginSendsNoCoordinates() {
        let api = FakeAPIClient()
        api.responseJSON = #"{"success": true, "places": []}"#
        let service = PlaceService(api: api)

        service.searchNetworkPlaces(query: "tacos", near: nil) { _ in }

        #expect(api.calls.first?.endpoint == "network/places/search?limit=50&query=tacos")
    }

    @Test func aMalformedPlaceDoesNotBlankTheList() throws {
        let api = FakeAPIClient()
        api.responseJSON = #"{"success": true, "places": [{"name": 7}]}"#
        let service = PlaceService(api: api)

        var received: Result<[Place], Error>?
        service.searchNetworkPlaces(query: "x", near: nil) { received = $0 }

        let places = try #require(try received?.get())
        #expect(places.isEmpty)
    }

    @Test func circlePlacesAskForThatCircle() {
        let api = FakeAPIClient()
        api.responseJSON = #"{"success": true, "places": []}"#
        let service = PlaceService(api: api)

        service.fetchPlacesByCircleId(circleId: "c42") { _ in }

        #expect(api.calls.count == 1)
        #expect(api.calls.first?.endpoint == "circles/c42/places")
    }
}
