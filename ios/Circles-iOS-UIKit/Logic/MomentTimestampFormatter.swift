import Foundation

/// How old a moment is, the way reels show it: "Just now", "10 minutes ago",
/// "3 hours ago", "2 days ago", and past a week the calendar date
/// ("September 3", with the year once it's from an earlier year).
enum MomentTimestampFormatter {
    /// Ages at or beyond this switch from "N days ago" to the calendar date.
    static let relativeCutoff: TimeInterval = 7 * 24 * 60 * 60

    static func string(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let age = now.timeIntervalSince(date)

        // Server stamps can run a little ahead of the device clock
        if age < 60 { return "Just now" }

        let minutes = Int(age / 60)
        if minutes < 60 { return plural(minutes, "minute") }

        let hours = Int(age / 3600)
        if hours < 24 { return plural(hours, "hour") }

        if age < relativeCutoff {
            return plural(Int(age / 86400), "day")
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMMd" : "MMMMdyyyy")
        return formatter.string(from: date)
    }

    private static func plural(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s") ago"
    }
}
