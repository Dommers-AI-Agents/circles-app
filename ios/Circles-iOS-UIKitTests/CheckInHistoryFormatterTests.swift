import Testing
import Foundation
@testable import Circles_iOS

/// The place page's "Checked in N times · last <day>" caption.
struct CheckInHistoryFormatterTests {
    private let locale = Locale(identifier: "en_US")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = locale
        return calendar
    }
    /// 2026-09-11 15:00:00 UTC
    private let now = Date(timeIntervalSince1970: 1_789_138_800)

    private func line(count: Int, lastDaysAgo: Double?) -> String? {
        let last = lastDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) }
        let stats = CheckInStats(count: count, firstCheckInAt: nil, lastCheckInAt: last)
        return CheckInHistoryFormatter.line(for: stats, now: now, calendar: calendar, locale: locale)
    }

    @Test func nothingToSayWhenNeverCheckedIn() {
        #expect(CheckInHistoryFormatter.line(for: nil) == nil)
        #expect(line(count: 0, lastDaysAgo: 1) == nil)
    }

    @Test func singleCheckInReadsOnce() {
        #expect(line(count: 1, lastDaysAgo: 0) == "Checked in once · last today")
    }

    @Test func recentDaysAreNamed() {
        #expect(line(count: 3, lastDaysAgo: 1) == "Checked in 3 times · last yesterday")
    }

    @Test func olderDatesUseTheShortDate() {
        #expect(line(count: 7, lastDaysAgo: 6) == "Checked in 7 times · last Sep 5")
    }

    @Test func earlierYearsCarryTheYear() {
        #expect(line(count: 2, lastDaysAgo: 400) == "Checked in 2 times · last Aug 7, 2025")
    }

    @Test func missingLastDateDropsTheSuffix() {
        #expect(line(count: 4, lastDaysAgo: nil) == "Checked in 4 times")
    }

    @Test func ordinals() {
        #expect(CheckInHistoryFormatter.ordinal(1, locale: locale) == "1st")
        #expect(CheckInHistoryFormatter.ordinal(2, locale: locale) == "2nd")
        #expect(CheckInHistoryFormatter.ordinal(3, locale: locale) == "3rd")
        #expect(CheckInHistoryFormatter.ordinal(11, locale: locale) == "11th")
        #expect(CheckInHistoryFormatter.ordinal(22, locale: locale) == "22nd")
    }
}
