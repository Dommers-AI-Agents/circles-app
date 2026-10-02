import Testing
import Foundation
@testable import Circles_iOS

/// The launch cache must read back what it wrote. It didn't: User.createdAt
/// came from the server as text, was saved as a number, and the next cold
/// start failed to decode it, dropped the cache and showed the loading
/// splash every time.
struct LaunchCacheRoundTripTests {

    private let serverUser = """
    {"_id":"u1","displayName":"Wes","profilePicture":null,"bio":null,"location":null,
     "friends":[],"friendRequests":[],"createdAt":"2025-07-01T12:30:00.000Z",
     "subscriptionExpiryDate":"2026-11-01T00:00:00Z","trialStartDate":"2026-10-01T00:00:00Z"}
    """

    @Test func aCachedUserReadsBack() throws {
        let user = try JSONDecoder().decode(User.self, from: Data(serverUser.utf8))
        #expect(user.createdAt != nil)
        let again = try JSONDecoder().decode(User.self, from: JSONEncoder().encode(user))
        #expect(again.createdAt == user.createdAt)
        #expect(again.subscriptionExpiryDate == user.subscriptionExpiryDate)
        #expect(again.trialStartDate == user.trialStartDate)
    }

    @Test func theWholeLaunchCacheReadsBack() throws {
        let user = try JSONDecoder().decode(User.self, from: Data(serverUser.utf8))
        let cache = PreloadedData(user: user, circles: [], networkCircles: [], allPlaces: [], connections: [],
                                  unreadMessageCount: 2, pendingConnectionCount: 1, activities: [], moments: [])
        let back = try JSONDecoder().decode(PreloadedData.self, from: JSONEncoder().encode(cache))
        #expect(back.user?.id == "u1")
        #expect(back.unreadMessageCount == 2)
    }

    @Test func everySpellingOfADate() {
        let when = Date(timeIntervalSince1970: 1_790_771_400) // 2026-09-30T12:30:00Z
        #expect(FlexibleDate.parse("2026-09-30T12:30:00.000Z") == when)
        #expect(FlexibleDate.parse("2026-09-30T12:30:00Z") == when)
        #expect(FlexibleDate.fromNumber(1_790_771_400) == when)
        #expect(FlexibleDate.fromNumber(1_790_771_400_000) == when)
        #expect(FlexibleDate.fromNumber(when.timeIntervalSinceReferenceDate) == when)
    }
}
