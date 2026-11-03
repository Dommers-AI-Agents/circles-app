import Testing
import Foundation
@testable import Circles_iOS

struct VenueActivityCopyTests {

    @Test func registerScansSayWhereThePhoneWas() {
        #expect(VenueActivityCopy.verb(type: "venue_visit", location: "near", offerTitle: nil).text == "bought something (register scan)")
        #expect(VenueActivityCopy.verb(type: "venue_visit", location: nil, offerTitle: nil).text == "bought something (register scan)")
        #expect(VenueActivityCopy.verb(type: "venue_visit", location: "off", offerTitle: nil).text.hasSuffix("location off)"))
        #expect(VenueActivityCopy.verb(type: "venue_visit", location: "unknown", offerTitle: nil).text.hasSuffix("location not checked)"))
    }

    @Test func scansThatEarnedNothingAreNamedAndKeptOutOfCharts() {
        for type in ["scan_far", "scan_repeat", "scan_removed"] {
            #expect(VenueActivityCopy.verb(type: type, location: nil, offerTitle: nil).text.hasSuffix("(no points)"))
            #expect(VenueActivityCopy.attemptTypes.contains(type))
        }
        #expect(!VenueActivityCopy.attemptTypes.contains("venue_visit"))
    }

    @Test func timeShowsSeconds() {
        let date = ISO8601DateFormatter().date(from: "2026-11-03T11:26:51Z")!
        let text = VenueActivityCopy.time(date, timeZone: TimeZone(identifier: "America/New_York")!, locale: Locale(identifier: "en_US"))
        #expect(text.contains("6:26:51"))
    }
}
