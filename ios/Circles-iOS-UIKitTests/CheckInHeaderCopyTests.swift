import Testing
@testable import Circles_iOS

/// The top of the Check In screen.
struct CheckInHeaderCopyTests {

    private func summary(total: Int = 10, streak: Int = 0, thisWeek: Bool = true,
                         friends: [CheckInSummary.Friend] = []) -> CheckInSummary {
        CheckInSummary(total: total, thisMonth: 2, places: 6, weekStreak: streak, checkedInThisWeek: thisWeek,
                       lastPlaceName: "Muraya", friendsOut: friends)
    }

    private func friend(_ name: String, at place: String? = nil) -> CheckInSummary.Friend {
        .init(userId: name, displayName: name, profilePicture: nil, placeName: place)
    }

    @Test func headlinePicksTheReason() {
        #expect(CheckInHeaderCopy.headline(nil) == "Where are you right now?")
        #expect(CheckInHeaderCopy.headline(summary(total: 0)) == "Your first check-in 📍")
        #expect(CheckInHeaderCopy.headline(summary(streak: 3, thisWeek: false)) == "Keep your 3-week streak alive 🔥")
        #expect(CheckInHeaderCopy.headline(summary(streak: 4)) == "4 weeks in a row 🔥")
        #expect(CheckInHeaderCopy.headline(summary(streak: 1)) == "Where are you right now?")
    }

    @Test func friendsLineNamesWhoIsOut() {
        #expect(CheckInHeaderCopy.friendsLine([]) == nil)
        #expect(CheckInHeaderCopy.friendsLine([friend("Brittany R", at: "Muraya")]) == "Brittany is out at Muraya")
        #expect(CheckInHeaderCopy.friendsLine([friend("Sal"), friend("Bill")]) == "Sal and 1 other are out right now")
        #expect(CheckInHeaderCopy.friendsLine([friend("Sal"), friend("Bill"), friend("Ann")]) == "Sal and 2 others are out right now")
    }

    @Test func tilesWaitForTheFirstCheckIn() {
        #expect(CheckInHeaderCopy.tiles(summary(total: 0)).isEmpty)
        let tiles = CheckInHeaderCopy.tiles(summary(total: 1, streak: 1))
        #expect(tiles.map(\.value) == ["🔥 1", "1", "6"])
        #expect(tiles.map(\.caption) == ["week streak", "check-in", "places"])
    }
}
