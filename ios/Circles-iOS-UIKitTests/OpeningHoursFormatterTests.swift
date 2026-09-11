import Testing
import Foundation
@testable import Circles_iOS

/// The place page's one-line "today" hours summary.
struct OpeningHoursFormatterTests {
    private func hour(_ json: String) -> OpeningHour {
        try! JSONDecoder().decode(OpeningHour.self, from: Data(json.utf8))
    }

    @Test func twelveHourTimes() {
        #expect(OpeningHoursFormatter.time("09:00") == "9 AM")
        #expect(OpeningHoursFormatter.time("00:30") == "12:30 AM")
        #expect(OpeningHoursFormatter.time("12:00") == "12 PM")
        #expect(OpeningHoursFormatter.time("17:05") == "5:05 PM")
        #expect(OpeningHoursFormatter.time("noon") == "noon")
    }

    @Test func openTodayUsesTodaysRow() {
        let hours = [
            hour(#"{"day":1,"open":"09:00","close":"17:30"}"#),
            hour(#"{"day":2,"open":"10:00","close":"22:00"}"#)
        ]
        #expect(OpeningHoursFormatter.todaySummary(hours, today: 2) == "Open today: 10 AM - 10 PM")
        #expect(OpeningHoursFormatter.todaySummary(hours, today: 1) == "Open today: 9 AM - 5:30 PM")
    }

    @Test func closedAndAllDay() {
        #expect(OpeningHoursFormatter.todaySummary([hour(#"{"day":0,"open":"09:00","close":"17:00","isClosed":true}"#)], today: 0) == "Closed today")
        #expect(OpeningHoursFormatter.todaySummary([hour(#"{"day":0,"open":"00:00","close":"00:00"}"#)], today: 0) == "Closed today")
        #expect(OpeningHoursFormatter.todaySummary([hour(#"{"day":0,"open":"00:00","close":"23:59"}"#)], today: 0) == "Open 24 hours")
    }

    @Test func legacyStringsAndMissingDays() {
        // The legacy decoder maps "Open 24 hours" / "Closed" text onto open/close
        #expect(OpeningHoursFormatter.todaySummary([hour(#"{"day":3,"hours":"Wednesday: Open 24 hours"}"#)], today: 3) == "Open 24 hours")
        #expect(OpeningHoursFormatter.todaySummary([hour(#"{"day":3,"hours":"Wednesday: Closed"}"#)], today: 3) == "Closed today")
        #expect(OpeningHoursFormatter.todaySummary([hour(#"{"day":3,"open":"09:00","close":"17:00"}"#)], today: 4) == "Hours not available")
        #expect(OpeningHoursFormatter.todaySummary([], today: 4) == "Hours not available")
    }

    @Test func todayIndexIsWeekdayMinusOne() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2026-09-11 is a Friday → 5
        #expect(OpeningHoursFormatter.todayIndex(calendar: calendar, now: Date(timeIntervalSince1970: 1_789_138_800)) == 5)
    }
}
