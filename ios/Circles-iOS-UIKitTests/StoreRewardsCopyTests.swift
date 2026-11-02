import Foundation
import Testing
@testable import Circles_iOS

struct StoreRewardsCopyTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    private let now = ISO8601DateFormatter().date(from: "2026-11-02T19:00:00Z")!

    private func history(lastVisitAt: String?) -> VenueRewardHistory {
        VenueRewardHistory(visits: lastVisitAt == nil ? 0 : 3, earned: 75, redeemed: 0, firstAt: nil, lastVisitAt: lastVisitAt, recent: [])
    }

    @Test func signedPoints() {
        #expect(StoreRewardsCopy.signedPoints(25) == "+25")
        #expect(StoreRewardsCopy.signedPoints(-100) == "\u{2212}100")
    }

    @Test func relativeDays() {
        #expect(StoreRewardsCopy.when("2026-11-02T14:00:00Z", now: now, calendar: calendar) == "Today")
        #expect(StoreRewardsCopy.when("2026-11-01T14:00:00.123Z", now: now, calendar: calendar) == "Yesterday")
        #expect(StoreRewardsCopy.when("2026-10-30T14:00:00Z", now: now, calendar: calendar) == "3 days ago")
        #expect(StoreRewardsCopy.when(nil, now: now, calendar: calendar) == nil)
    }

    @Test func lastVisitLine() {
        #expect(StoreRewardsCopy.lastVisitLine(history(lastVisitAt: "2026-11-01T14:00:00Z"), now: now, calendar: calendar) == "Last visit yesterday")
        #expect(StoreRewardsCopy.lastVisitLine(history(lastVisitAt: "2026-10-30T14:00:00Z"), now: now, calendar: calendar) == "Last visit 3 days ago")
        #expect(StoreRewardsCopy.lastVisitLine(history(lastVisitAt: nil), now: now, calendar: calendar).hasPrefix("No visits yet"))
    }

    @Test func noOffersKeepsThePointsMeaningful() {
        #expect(StoreRewardsCopy.noOffersLine(venueName: "Pasta & Provisions", balance: 50)
                == "Pasta & Provisions hasn't posted rewards yet. Your 50 points stay saved here for when they do.")
        #expect(StoreRewardsCopy.noOffersLine(venueName: "X", balance: 0).contains("Points you earn now"))
    }
}
