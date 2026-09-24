import Foundation
import Testing
@testable import Circles_iOS

/// The Always-location check-in banner: fires for a stop, never a drive-by,
/// and never more than a few times a day.
struct DwellCheckInGateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func context(prompted: Bool = false, today: Int = 0, lastArmed: TimeInterval? = nil) -> DwellCheckInGate.EntryContext {
        .init(promptedTodayForPlace: prompted, promptsToday: today,
              lastArmedAt: lastArmed.map { now.addingTimeInterval(-$0) }, now: now)
    }

    @Test func onlyWithAlwaysAndNotificationsAndThePreference() {
        #expect(DwellCheckInGate.isAvailable(isAlwaysAuthorized: true, notificationsAuthorized: true, preferenceOn: true))
        #expect(!DwellCheckInGate.isAvailable(isAlwaysAuthorized: false, notificationsAuthorized: true, preferenceOn: true))
        #expect(!DwellCheckInGate.isAvailable(isAlwaysAuthorized: true, notificationsAuthorized: false, preferenceOn: true))
        #expect(!DwellCheckInGate.isAvailable(isAlwaysAuthorized: true, notificationsAuthorized: true, preferenceOn: false))
    }

    @Test func aFirstEntryArms() {
        #expect(DwellCheckInGate.shouldArm(context()))
    }

    @Test func onceADayPerPlace() {
        #expect(!DwellCheckInGate.shouldArm(context(prompted: true)))
    }

    /// Sal's drive: five saved places in thirteen minutes. Even if he stopped
    /// at all five, the second within half an hour stays quiet.
    @Test func halfAnHourBetweenBannersWhateverThePlace() {
        #expect(!DwellCheckInGate.shouldArm(context(lastArmed: 10 * 60)))
        #expect(DwellCheckInGate.shouldArm(context(lastArmed: 31 * 60)))
    }

    @Test func threeADayAtMost() {
        #expect(DwellCheckInGate.shouldArm(context(today: 2, lastArmed: 2 * 3600)))
        #expect(!DwellCheckInGate.shouldArm(context(today: 3, lastArmed: 2 * 3600)))
    }

    @Test func identifiersRoundTrip() {
        #expect(DwellCheckInGate.placeId(fromIdentifier: "dwell.abc") == "abc")
        #expect(DwellCheckInGate.placeId(fromIdentifier: "proximity.abc") == nil)
        #expect(DwellCheckInGate.placeId(fromIdentifier: "dwell.") == nil)
    }

    @Test func fiveMinutesIsAStopNotADriveBy() {
        #expect(DwellCheckInGate.dwellSeconds == 300)
    }
}
