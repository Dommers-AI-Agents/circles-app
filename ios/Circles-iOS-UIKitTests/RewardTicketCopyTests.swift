import Foundation
import Testing
@testable import Circles_iOS

/// Reward tickets: what the customer and the store see (2026-11-01)
struct RewardTicketCopyTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private let now = ISO8601DateFormatter().date(from: "2026-11-01T22:00:00Z")!

    private func ticket(_ status: String, givenAt: String? = nil) -> RewardVoucher {
        RewardVoucher(voucherCode: "AB12", offerTitle: "Free drip coffee", pointsCost: 100, venueName: "Sal's",
                      expiresAt: "2026-11-01T22:10:00Z", voucherId: "r1", venueId: "v1", status: status, givenAt: givenAt)
    }

    @Test func customerLines() {
        #expect(RewardTicketCopy.historyLine(ticket("issued"), calendar: calendar, now: now).isOpen)
        let given = RewardTicketCopy.historyLine(ticket("given", givenAt: "2026-11-01T21:54:00Z"), calendar: calendar, now: now)
        #expect(given.text.hasPrefix("Free drip coffee at Sal's · Given today"))
        #expect(!given.isOpen)
        #expect(RewardTicketCopy.historyLine(ticket("expired"), calendar: calendar, now: now).text
                == "Free drip coffee at Sal's · Not used, 100 points back")
    }

    @Test func storeLines() {
        let row = VenueRewardTicket(voucherId: "r1", offerTitle: "Free drip coffee", pointsCost: 100, voucherCode: "AB12",
                                    createdAt: "2026-11-01T21:50:00Z", status: "expired", givenAt: nil, customerName: "Sal")
        #expect(VenueRewardTicketCopy.line(row, calendar: calendar, now: now).detail.hasPrefix("Not given · points returned"))
        let open = VenueRewardTicket(voucherId: "r2", offerTitle: "Latte", pointsCost: 50, voucherCode: "ZZ99",
                                     createdAt: "2026-11-01T21:58:00Z", status: "issued", givenAt: nil, customerName: "Ann")
        #expect(VenueRewardTicketCopy.line(open, calendar: calendar, now: now).status == "issued")
    }

    @Test func expiredTicketsAreLeftOut() {
        let kept = RewardTicketCopy.shown([ticket("issued"), ticket("expired"), ticket("given", givenAt: "2026-11-01T21:54:00Z")])
        #expect(kept.map(\.status) == ["issued", "given"])
    }
}
