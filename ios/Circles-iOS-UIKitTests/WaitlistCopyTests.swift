import Testing
import Foundation
@testable import Circles_iOS

/// A store's waitlist wording, guest and host.
struct WaitlistCopyTests {

    private func entry(status: String = "waiting", position: Int? = 3, estimate: Int? = 40, party: Int = 2,
                       name: String? = "Ana", joinedAt: String? = nil, notifiedAt: String? = nil) -> WaitlistEntry {
        WaitlistEntry(entryId: "e1", venueId: "v1", venueName: "Sal's", placeId: "gp1", userId: "u1", name: name,
                      partySize: party, status: status, joinedAt: joinedAt, notifiedAt: notifiedAt,
                      position: position, estimateMinutes: estimate, holdMinutes: 15, alreadyInLine: nil)
    }

    @Test func guestStatusLines() {
        #expect(WaitlistCopy.statusLine(entry()) == "You're #3 in line · about 40 min")
        #expect(WaitlistCopy.statusLine(entry(position: 1, estimate: nil)) == "You're #1 in line")
        #expect(WaitlistCopy.statusLine(entry(status: "notified")) == "Your table is ready — head to the host stand")
        #expect(WaitlistCopy.partyLine(1) == "Party of 1")
        #expect(WaitlistCopy.joinExplanation(quoteMinutes: 20).contains("20 minutes per party"))
    }

    @Test func hostRowsSayWhoHowManyAndHowLong() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let iso = ISO8601DateFormatter()
        let joined = iso.string(from: now.addingTimeInterval(-12 * 60))
        let called = iso.string(from: now.addingTimeInterval(-3 * 60))
        #expect(WaitlistCopy.hostRow(entry(joinedAt: joined), now: now) == "Ana · party of 2 · waiting 12 min")
        #expect(WaitlistCopy.hostRow(entry(status: "notified", joinedAt: joined, notifiedAt: called), now: now) == "Ana · party of 2 · called 3 min")
        #expect(WaitlistCopy.hostRow(entry(party: 1, name: nil, joinedAt: iso.string(from: now)), now: now) == "Guest · party of 1 · waiting just now")
        #expect(WaitlistCopy.lineHeader(count: 0) == "Nobody is waiting")
        #expect(WaitlistCopy.lineHeader(count: 2) == "2 parties waiting")
    }

    @Test func settingsAndRowSummaries() {
        #expect(WaitlistCopy.rowSummary(enabled: false, waiting: 0).hasPrefix("Off"))
        #expect(WaitlistCopy.rowSummary(enabled: true, waiting: 0) == "On · nobody waiting")
        #expect(WaitlistCopy.rowSummary(enabled: true, waiting: 3) == "On · 3 parties waiting")
        #expect(WaitlistCopy.settingsFooter(enabled: true, quoteMinutes: 15).contains("15 minutes per party"))
        #expect(WaitlistCopy.quoteOptions.first == 5)
        for text in [WaitlistCopy.settingsFooter(enabled: true, quoteMinutes: 15), WaitlistCopy.settingsFooter(enabled: false, quoteMinutes: 15), WaitlistCopy.joinExplanation(quoteMinutes: 15)] {
            #expect(!text.lowercased().contains(" text"), "\(text)")
            #expect(!text.lowercased().contains("sms"), "\(text)")
        }
    }
}
