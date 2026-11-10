import Foundation

/// Words for the My check-ins screen: the header's numbers and each
/// place's line. Pure, so the wording is unit-tested.
enum MyCheckInsCopy {
    static let title = "My check-ins"
    static let emptyTitle = "No check-ins yet\n\nCheck in when you're out and every place you go lands here, with how often you've been."

    /// "42 check-ins at 17 places" / "1 check-in at 1 place"
    static func headline(total: Int, places: Int) -> String {
        let checkIns = total == 1 ? "1 check-in" : "\(total) check-ins"
        let spots = places == 1 ? "1 place" : "\(places) places"
        return "\(checkIns) at \(spots)"
    }

    /// "5 in the last 30 days", or nil when there were none
    static func recent(_ count: Int, days: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(count) in the last \(days) days"
    }

    /// Each row's second line: the place page's own caption
    /// ("Checked in 7 times · last Sep 5"), then the first time here.
    static func detail(for place: CheckInPlaceSummary, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        var line = CheckInHistoryFormatter.line(for: place.stats, now: now, calendar: calendar, locale: locale) ?? "Checked in"
        if place.count > 1, let first = place.firstCheckInAt {
            line += " · first \(CheckInHistoryFormatter.dayLabel(for: first, now: now, calendar: calendar, locale: locale))"
        }
        return line
    }

    /// The badge beside a place with recent check-ins: "×3 lately"
    static func recentBadge(_ count: Int) -> String? {
        count > 0 ? "×\(count) lately" : nil
    }
}
