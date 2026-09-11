import Testing
import Foundation
@testable import Circles_iOS

/// Moments show their age like reels do: relative for the first week, then
/// the calendar date.
struct MomentTimestampFormatterTests {
    private let locale = Locale(identifier: "en_US")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = locale
        return calendar
    }
    /// 2026-09-11 15:00:00 UTC
    private let now = Date(timeIntervalSince1970: 1_789_138_800)

    private func format(secondsAgo: TimeInterval) -> String {
        MomentTimestampFormatter.string(for: now.addingTimeInterval(-secondsAgo), now: now, calendar: calendar, locale: locale)
    }

    @Test func underAMinuteIsJustNow() {
        #expect(format(secondsAgo: 0) == "Just now")
        #expect(format(secondsAgo: 30) == "Just now")
        #expect(format(secondsAgo: 59) == "Just now")
    }

    @Test func futureStampsFromClockSkewAreJustNow() {
        #expect(format(secondsAgo: -120) == "Just now")
    }

    @Test func minutes() {
        #expect(format(secondsAgo: 60) == "1 minute ago")
        #expect(format(secondsAgo: 10 * 60) == "10 minutes ago")
        #expect(format(secondsAgo: 59 * 60 + 59) == "59 minutes ago")
    }

    @Test func hours() {
        #expect(format(secondsAgo: 60 * 60) == "1 hour ago")
        #expect(format(secondsAgo: 5 * 60 * 60 + 30 * 60) == "5 hours ago")
        #expect(format(secondsAgo: 23 * 60 * 60 + 59 * 60) == "23 hours ago")
    }

    @Test func daysUpToAWeek() {
        #expect(format(secondsAgo: 24 * 60 * 60) == "1 day ago")
        #expect(format(secondsAgo: 3 * 24 * 60 * 60) == "3 days ago")
        #expect(format(secondsAgo: 7 * 24 * 60 * 60 - 1) == "6 days ago")
    }

    @Test func aWeekOrOlderShowsTheDate() {
        #expect(format(secondsAgo: 7 * 24 * 60 * 60) == "September 4")
        #expect(format(secondsAgo: 40 * 24 * 60 * 60) == "August 2")
    }

    @Test func earlierYearIncludesTheYear() {
        #expect(format(secondsAgo: 300 * 24 * 60 * 60) == "November 15, 2025")
    }
}
