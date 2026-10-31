import Foundation
import Testing
@testable import Circles_iOS

/// The App Clip writes ClipHandoff.Welcome; the app reads it as ClipWelcome.
/// This is the clip's JSON shape, so a field renamed on one side fails here.
@Suite struct ClipWelcomeTests {
    private let clipJSON = """
    {"code":"ABC123","kind":"register",
     "venue":{"venueId":"v1","venueName":"Test Bakery (Demo)","placeName":null,"placeAddress":"1 Main St",
              "category":"bakery","googlePlaceId":null,"globalPlaceId":"g1","location":{"lat":35.2,"lng":-80.8}},
     "awardedPoints":25,"venueBalance":25,"earnRate":25,
     "offers":[{"title":"Free croissant","pointsCost":100}],
     "nextRewardLine":"75 more points for a free croissant","alreadySaved":false}
    """

    @Test func decodesWhatTheClipWrites() throws {
        let welcome = try JSONDecoder().decode(ClipWelcome.self, from: Data(clipJSON.utf8))
        #expect(welcome.venue.globalPlaceId == "g1")
        #expect(welcome.awardedPoints == 25)
        #expect(welcome.offers.first?.title == "Free croissant")
        #expect(welcome.alreadySaved == false)
    }

    @Test func stashIsTakenOnce() throws {
        let welcome = try JSONDecoder().decode(ClipWelcome.self, from: Data(clipJSON.utf8))
        ClipWelcome.stash(welcome)
        #expect(ClipWelcome.takeStashed()?.code == "ABC123")
        #expect(ClipWelcome.takeStashed() == nil)
    }
}
