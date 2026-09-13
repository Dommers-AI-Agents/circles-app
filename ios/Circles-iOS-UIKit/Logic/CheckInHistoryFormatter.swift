import Foundation

/// The viewer's own check-in history at a venue, as served on a place
/// (`myCheckInStats`). Only ever the current user's — never anyone else's.
struct CheckInStats: Codable, Equatable {
    let count: Int
    let firstCheckInAt: Date?
    let lastCheckInAt: Date?
}

/// One-line caption for the place page: "Checked in 7 times · last Sep 5".
/// Pure — no UIKit, no services — so the wording is unit-tested.
enum CheckInHistoryFormatter {
    static func line(
        for stats: CheckInStats?,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        guard let stats = stats, stats.count > 0 else { return nil }
        let times = stats.count == 1 ? "once" : "\(stats.count) times"
        var line = "Checked in \(times)"
        if let last = stats.lastCheckInAt {
            line += " · last \(dayLabel(for: last, now: now, calendar: calendar, locale: locale))"
        }
        return line
    }

    /// "1st", "2nd", "3rd", "11th"… for the post-check-in toast.
    static func ordinal(_ n: Int, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// "today", "yesterday", then the calendar date ("Sep 5", with the year
    /// once it's from an earlier year).
    static func dayLabel(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdyyyy")
        return formatter.string(from: date)
    }
}
