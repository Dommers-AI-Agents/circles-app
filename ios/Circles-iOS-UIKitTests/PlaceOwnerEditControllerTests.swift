import Testing
@testable import Circles_iOS

/// The owner description editor works on prose only: legacy "Phone:" /
/// "Website:" lines embedded in old descriptions are stripped on the way
/// in and out.
struct PlaceOwnerEditControllerTests {
    @Test func stripsLegacyContactLinesAndTrims() {
        let text = "  Great coffee.\nPhone: 555-1234\n\nOpen late.\n  Website: https://x.test\n"
        #expect(PlaceOwnerEditController.strippingContactLines(text) == "Great coffee.\n\nOpen late.")
    }

    @Test func collapsesTripleBlankLinesLeftByAStrippedLine() {
        let text = "One\n\nPhone: 1\n\nTwo"
        #expect(PlaceOwnerEditController.strippingContactLines(text) == "One\n\nTwo")
    }

    @Test func keepsProseThatMerelyMentionsAPhone() {
        #expect(PlaceOwnerEditController.strippingContactLines("Call the phone: it's fine") == "Call the phone: it's fine")
        #expect(PlaceOwnerEditController.strippingContactLines(nil) == "")
    }
}
