import Testing
import Foundation
@testable import Circles_iOS

/// Reading the server's "you already saved this place" answer.
struct PlaceDuplicateTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func readsTheAnswer() {
        let dup = PlaceDuplicate.from(json: data(#"{"success":false,"code":"DUPLICATE_PLACE","existingPlaceId":"p1","existingPlaceName":"Atlantic Club","existingCircleId":"c1","existingCircleName":"Gym"}"#))
        #expect(dup == PlaceDuplicate(placeId: "p1", placeName: "Atlantic Club", circleId: "c1", circleName: "Gym"))
        #expect(dup?.message == "You already have \"Atlantic Club\" in your \"Gym\" circle. What would you like to do?")
    }

    @Test func olderServersWithoutTheCircleStillWork() {
        let dup = PlaceDuplicate.from(json: data(#"{"code":"DUPLICATE_PLACE","existingPlaceId":"p1"}"#))
        #expect(dup?.message == "You already saved this place. What would you like to do?")
    }

    @Test func otherErrorsAreNotDuplicates() {
        #expect(PlaceDuplicate.from(json: data(#"{"code":"PLACE_LIMIT","message":"Upgrade to premium"}"#)) == nil)
        #expect(PlaceDuplicate.from(json: data("not json")) == nil)
        #expect(PlaceDuplicate.from(APIError.noInternet) == nil)
        #expect(PlaceDuplicate.from(APIError.httpError(400, data(#"{"code":"DUPLICATE_PLACE","existingPlaceId":"p9"}"#)))?.placeId == "p9")
    }
}
