import Testing
import Foundation
@testable import Circles_iOS

/// The owner's "sent" rows in the home feed (postcards, Fridge Mail) used to
/// decode as an unknown type: "shared an update", no picture, a dead tap.
struct OwnSentActivityTests {

    private func activity(_ type: String, name: String = "Linda Sgroi") throws -> Activity {
        let json = """
        {"_id":"a1","type":"\(type)","actorId":"wes","targetType":"fridge_mail","targetId":"fm_1",
         "targetName":"\(name)","timestamp":"2026-10-05T15:00:04Z",
         "metadata":{"imageUrl":"https://example.com/drawing.jpg","recipientName":"\(name)","ownerOnly":true}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Activity.self, from: Data(json.utf8))
    }

    @Test func fridgeMailAndPostcardsReadAsWhatHappened() throws {
        let fridge = try activity("fridgemail_sent")
        #expect(fridge.type == .fridgemailSent)
        #expect(fridge.formattedDescription == "mailed Fridge Mail to Linda Sgroi")
        #expect(fridge.metadata?.imageUrl == "https://example.com/drawing.jpg")
        #expect(try activity("postcard_sent", name: "Mom").formattedDescription == "sent a postcard to Mom")
        #expect(try activity("postcard_mailed", name: "Mom").formattedDescription == "mailed a printed postcard to Mom")
    }

    @Test func aTypeThisBuildDoesNotKnowStillDecodes() throws {
        #expect(try activity("something_new").type == .unknown)
    }
}
