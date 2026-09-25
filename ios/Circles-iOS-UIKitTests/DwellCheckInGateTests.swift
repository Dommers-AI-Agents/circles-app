import Foundation
import Testing
@testable import Circles_iOS

/// The Always-location check-in banner's budget: a few a day at most, never
/// two close together, and a way out from the second one on.
struct DwellCheckInGateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func context(prompted: Bool = false, today: Int = 0, lastFired: TimeInterval? = nil) -> DwellCheckInGate.EntryContext {
        .init(promptedTodayForPlace: prompted, promptsToday: today,
              lastFiredAt: lastFired.map { now.addingTimeInterval(-$0) }, now: now)
    }

    @Test func onlyWithAlwaysAndNotificationsAndThePreference() {
        #expect(DwellCheckInGate.isAvailable(isAlwaysAuthorized: true, notificationsAuthorized: true, preferenceOn: true))
        #expect(!DwellCheckInGate.isAvailable(isAlwaysAuthorized: false, notificationsAuthorized: true, preferenceOn: true))
        #expect(!DwellCheckInGate.isAvailable(isAlwaysAuthorized: true, notificationsAuthorized: false, preferenceOn: true))
        #expect(!DwellCheckInGate.isAvailable(isAlwaysAuthorized: true, notificationsAuthorized: true, preferenceOn: false))
    }

    @Test func aFirstArrivalPrompts() {
        #expect(DwellCheckInGate.shouldPrompt(context()))
    }

    @Test func onceADayPerPlace() {
        #expect(!DwellCheckInGate.shouldPrompt(context(prompted: true)))
    }

    /// Sal's drive: five saved places in thirteen minutes. Even if he walked
    /// into all five, the second within half an hour stays quiet.
    @Test func halfAnHourBetweenBannersWhateverThePlace() {
        #expect(!DwellCheckInGate.shouldPrompt(context(lastFired: 10 * 60)))
        #expect(DwellCheckInGate.shouldPrompt(context(lastFired: 31 * 60)))
    }

    @Test func threeADayAtMost() {
        #expect(DwellCheckInGate.shouldPrompt(context(today: 2, lastFired: 2 * 3600)))
        #expect(!DwellCheckInGate.shouldPrompt(context(today: 3, lastFired: 2 * 3600)))
    }

    @Test func offersOptOutFromTheSecondBannerOfTheDay() {
        #expect(!DwellCheckInGate.offersOptOut(promptsToday: 0))
        #expect(DwellCheckInGate.offersOptOut(promptsToday: 1))
        #expect(DwellCheckInGate.offersOptOut(promptsToday: 2))
    }

    @Test func identifiersRoundTrip() {
        #expect(DwellCheckInGate.placeId(fromIdentifier: "dwell.abc") == "abc")
        #expect(DwellCheckInGate.placeId(fromIdentifier: "proximity.abc") == nil)
        #expect(DwellCheckInGate.placeId(fromIdentifier: "dwell.") == nil)
    }
}
