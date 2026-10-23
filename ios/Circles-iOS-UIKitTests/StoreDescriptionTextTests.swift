import Testing
@testable import Circles_iOS

/// The owner description editor works on prose only: legacy "Phone:" /
/// "Website:" lines embedded in old descriptions are stripped on the way
/// in and out.
struct StoreDescriptionTextTests {
    @Test func stripsLegacyContactLinesAndTrims() {
        let text = "  Great coffee.\nPhone: 555-1234\n\nOpen late.\n  Website: https://x.test\n"
        #expect(StoreDescriptionText.strippingContactLines(text) == "Great coffee.\n\nOpen late.")
    }

    @Test func collapsesTripleBlankLinesLeftByAStrippedLine() {
        let text = "One\n\nPhone: 1\n\nTwo"
        #expect(StoreDescriptionText.strippingContactLines(text) == "One\n\nTwo")
    }

    @Test func keepsProseThatMerelyMentionsAPhone() {
        #expect(StoreDescriptionText.strippingContactLines("Call the phone: it's fine") == "Call the phone: it's fine")
        #expect(StoreDescriptionText.strippingContactLines(nil) == "")
    }
}
