import Testing
import Foundation
@testable import Circles_iOS

/// The Face ID offer after an instant sign-up: at most twice, days apart
/// (Wes, 2026-11-12: a new tester was asked three times in one session).
struct AccountSafetyPromptTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func firstAskIsRightAway() {
        #expect(AccountSafetyPrompt.shouldAsk(timesAsked: 0, lastAskedAt: nil, now: now))
    }

    @Test func neverTwiceInOneSessionOrWithinThreeDays() {
        #expect(!AccountSafetyPrompt.shouldAsk(timesAsked: 1, lastAskedAt: now.addingTimeInterval(-60), now: now))
        #expect(!AccountSafetyPrompt.shouldAsk(timesAsked: 1, lastAskedAt: now.addingTimeInterval(-2.9 * 86400), now: now))
        #expect(AccountSafetyPrompt.shouldAsk(timesAsked: 1, lastAskedAt: now.addingTimeInterval(-3 * 86400), now: now))
    }

    @Test func neverAThirdTime() {
        #expect(!AccountSafetyPrompt.shouldAsk(timesAsked: 2, lastAskedAt: now.addingTimeInterval(-30 * 86400), now: now))
    }
}
