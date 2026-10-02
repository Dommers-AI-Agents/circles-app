import Testing
import Foundation
@testable import Circles_iOS

/// When the app may ask for an App Store rating.
struct ReviewPromptPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    private func state(moments: Int = 5, firstSeenDaysAgo: Double = 10,
                       lastAskedDaysAgo: Double? = nil, lastVersion: String? = nil) -> ReviewPromptPolicy.State {
        ReviewPromptPolicy.State(happyMoments: moments, firstSeen: daysAgo(firstSeenDaysAgo),
                                 lastAsked: lastAskedDaysAgo.map(daysAgo), lastAskedVersion: lastVersion)
    }

    @Test func asksAHappySettledUserWhoWasNeverAsked() {
        #expect(ReviewPromptPolicy.shouldAsk(state(), appVersion: "1.3.8", now: now))
    }

    @Test func waitsForEnoughGoodMomentsAndDays() {
        #expect(!ReviewPromptPolicy.shouldAsk(state(moments: 2), appVersion: "1.3.8", now: now))
        #expect(!ReviewPromptPolicy.shouldAsk(state(firstSeenDaysAgo: 2), appVersion: "1.3.8", now: now))
        #expect(ReviewPromptPolicy.shouldAsk(state(moments: 3, firstSeenDaysAgo: 3), appVersion: "1.3.8", now: now))
    }

    @Test func onceAVersionAndNotWithinNinetyDays() {
        #expect(!ReviewPromptPolicy.shouldAsk(state(lastAskedDaysAgo: 200, lastVersion: "1.3.8"), appVersion: "1.3.8", now: now))
        #expect(!ReviewPromptPolicy.shouldAsk(state(lastAskedDaysAgo: 30, lastVersion: "1.3.7"), appVersion: "1.3.8", now: now))
        #expect(ReviewPromptPolicy.shouldAsk(state(lastAskedDaysAgo: 91, lastVersion: "1.3.7"), appVersion: "1.3.8", now: now))
    }
}
