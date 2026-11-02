import Testing
import Foundation
@testable import Circles_iOS

struct VenueCustomerCopyTests {

    private func customer(purchases: Int = 12, rewards: Int = 2, points: Int = 75, last: String? = nil, removed: Bool = false) -> VenueCustomer {
        VenueCustomer(user: .init(id: "u1", displayName: "Ann", username: nil, profilePicture: nil),
                      email: nil, sharedWithStore: false, points: points, purchases: purchases,
                      rewardsClaimed: rewards, lastScanAt: last, removed: removed)
    }

    @Test func countsPointsAndLastVisit() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-11-02T18:00:00Z")!
        let line = VenueCustomerCopy.detail(customer(last: "2026-11-02T15:10:00.000Z"), calendar: calendar, now: now)
        #expect(line.hasPrefix("12 purchases \u{00B7} 2 rewards \u{00B7} 75 pts \u{00B7} last today"))
    }

    @Test func singularsAndNoVisitYet() {
        #expect(VenueCustomerCopy.detail(customer(purchases: 1, rewards: 1, points: 25)) == "1 purchase \u{00B7} 1 reward \u{00B7} 25 pts")
    }

    @Test func removedSaysSo() {
        #expect(VenueCustomerCopy.detail(customer(removed: true)) == "Removed from your rewards")
    }
}
