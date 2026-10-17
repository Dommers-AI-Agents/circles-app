import Testing
@testable import Circles_iOS

/// The owner's confirmation after posting (2026-10-17).
struct StoreAlertCopyTests {
    @Test func nothingToSayWhenNobodyHasAlertsOn() {
        #expect(StoreAlertCopy.line(nil) == nil)
        #expect(StoreAlertCopy.line(StoreAlertResult(audience: 0, sent: 0, throttled: false)) == nil)
    }

    @Test func namesWhoWasAlerted() {
        #expect(StoreAlertCopy.line(StoreAlertResult(audience: 1, sent: 1, throttled: false))
                == "Posted, and sent as an alert to 1 follower who turned on alerts.")
        #expect(StoreAlertCopy.line(StoreAlertResult(audience: 12, sent: 11, throttled: false))?.contains("12 followers") == true)
    }

    @Test func saysWhenTheDailyAlertWasAlreadyUsed() {
        #expect(StoreAlertCopy.line(StoreAlertResult(audience: 3, sent: 0, throttled: true))?.contains("already alerted your 3 followers today") == true)
    }
}
