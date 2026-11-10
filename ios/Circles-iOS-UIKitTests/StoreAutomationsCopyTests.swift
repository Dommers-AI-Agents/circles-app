import Testing
import Foundation
@testable import Circles_iOS

/// The store's automatic nudges: owner wording and the customer's birthday.
struct StoreAutomationsCopyTests {

    private typealias C = StoreAutomationsCopy

    @Test func summaryNamesWhatIsOn() {
        var settings = StoreAutomations.off
        #expect(C.summary(settings) == "Off: automatic win-back, birthday and almost-there nudges")
        settings.winBack.enabled = true
        settings.almostThere.enabled = true
        #expect(C.summary(settings) == "On: win-back, almost there")
    }

    @Test func linesForBonusDaysAndResults() {
        #expect(C.bonusLine(0) == "No bonus, just the note")
        #expect(C.bonusLine(50) == "+50 bonus points on the next visit")
        #expect(C.winBackDetail(days: 60) == "After 60 days without a purchase")
        #expect(C.statsLine(sent: 0, cameBack: 0) == "Nothing sent yet")
        #expect(C.statsLine(sent: 12, cameBack: 5) == "Sent 12 · 5 came back")
        #expect(C.winBackDays == [14, 30, 60, 90])
    }

    @Test func neverPromisesTexting() {
        let all = C.Kind.allCases.map(\.explanation) + [C.pageFooter, C.birthdayExplanation]
        for text in all {
            #expect(!text.lowercased().contains("text"), "\(text)")
            #expect(!text.lowercased().contains("sms"), "\(text)")
        }
    }

    @Test func birthdayIsMonthAndDayOnly() {
        var parts = DateComponents()
        parts.year = 1988; parts.month = 3; parts.day = 14
        let date = Calendar.current.date(from: parts)!
        #expect(C.birthdayValue(from: date) == "03-14")
        #expect(C.birthdayLabel("03-14") == "March 14")
        #expect(C.birthdayLabel("13-01") == nil)
        #expect(C.birthdayRowDetail(nil) == "Stores you earn with can send a birthday reward")
        #expect(C.birthdayRowDetail("12-25") == "Your birthday: December 25")
    }

    @Test func settingsBodyMatchesTheServerShape() {
        var settings = StoreAutomations.off
        settings.winBack = .init(enabled: true, days: 60, bonusPoints: 25)
        let body = settings.asBody
        let winBack = body["winBack"] as? [String: Any]
        #expect(winBack?["enabled"] as? Bool == true)
        #expect(winBack?["days"] as? Int == 60)
        #expect(winBack?["bonusPoints"] as? Int == 25)
        #expect((body["almostThere"] as? [String: Any])?["enabled"] as? Bool == false)
    }
}
