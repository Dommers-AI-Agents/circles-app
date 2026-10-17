import Foundation

/// "Scan a time period" for Add from photos (Wes, 2026-10-17): a month or
/// two (a trip), a whole year, a range, or every photo. Pure, tested.
enum PhotoPeriod: Hashable {
    /// The first day of a month
    case month(Date)
    case year(Int)
    case range(DateInterval)
    case all

    func interval(calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .month(let start): return calendar.dateInterval(of: .month, for: start)
        case .year(let year):
            guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }
            return calendar.dateInterval(of: .year, for: start)
        case .range(let interval): return interval
        case .all: return nil
        }
    }

    /// Months that have photos, newest first, with how many (at most `limit`)
    static func months(of dates: [Date], limit: Int = 24, calendar: Calendar = .current) -> [(start: Date, count: Int)] {
        var counts: [Date: Int] = [:]
        for date in dates {
            if let start = calendar.dateInterval(of: .month, for: date)?.start { counts[start, default: 0] += 1 }
        }
        return counts.sorted { $0.key > $1.key }.prefix(limit).map { ($0.key, $0.value) }
    }

    /// Years that have photos, newest first, with how many
    static func years(of dates: [Date], calendar: Calendar = .current) -> [(year: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for date in dates { counts[calendar.component(.year, from: date), default: 0] += 1 }
        return counts.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }

    /// Whether a photo taken at `date` is in any of the periods
    static func contains(_ periods: Set<PhotoPeriod>, _ date: Date, calendar: Calendar = .current) -> Bool {
        if periods.contains(.all) { return true }
        return periods.contains { $0.interval(calendar: calendar)?.contains(date) ?? false }
    }

    /// The new circle's default name: "Charleston · Sep 2026", "Sep–Oct 2026",
    /// "2025", "All my photos"; `place` is where most of the photos were.
    static func circleName(_ periods: Set<PhotoPeriod>, place: String?, calendar: Calendar = .current) -> String {
        if periods.contains(.all) || periods.isEmpty { return "All my photos" }
        let intervals = periods.compactMap { $0.interval(calendar: calendar) }.sorted { $0.start < $1.start }
        guard let first = intervals.first, let last = intervals.last else { return "My photos" }
        let span = DateInterval(start: first.start, end: last.end.addingTimeInterval(-1))
        let label: String
        if periods.count == 1, case .year(let year)? = periods.first {
            label = String(year)
        } else {
            let month = DateFormatter()
            month.calendar = calendar
            month.locale = calendar.locale ?? .current
            month.setLocalizedDateFormatFromTemplate("MMM yyyy")
            let monthOnly = DateFormatter()
            monthOnly.calendar = calendar
            monthOnly.locale = calendar.locale ?? .current
            monthOnly.setLocalizedDateFormatFromTemplate("MMM")
            let sameMonth = calendar.isDate(span.start, equalTo: span.end, toGranularity: .month)
            let sameYear = calendar.isDate(span.start, equalTo: span.end, toGranularity: .year)
            if sameMonth {
                label = month.string(from: span.start)
            } else if sameYear {
                label = "\(monthOnly.string(from: span.start))\u{2013}\(month.string(from: span.end))"
            } else {
                label = "\(month.string(from: span.start)) \u{2013} \(month.string(from: span.end))"
            }
        }
        guard let place, !place.isEmpty else { return label }
        return String("\(place) \u{00B7} \(label)".prefix(50))
    }
}
