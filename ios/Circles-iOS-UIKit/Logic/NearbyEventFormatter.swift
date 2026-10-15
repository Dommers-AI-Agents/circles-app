import Foundation

/// The words on a "Happening nearby" row. Pure, so the date rules are tested.
enum NearbyEventFormatter {
    /// "Tonight · 8:00 PM", "Tomorrow · 7:30 PM", "Sat, Oct 18 · 8:00 PM".
    /// The venue's local date and time are shown as they are — an event
    /// in another time zone still reads at its own clock time.
    static func dateLine(localDate: String, localTime: String?, now: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = localDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return localDate
        }
        let today = calendar.startOfDay(for: now)
        let dayDiff = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: day)).day ?? 99
        let time = timeText(localTime, calendar: calendar)

        let dayText: String
        switch dayDiff {
        case 0: dayText = (hour(localTime) ?? 0) >= 17 ? "Tonight" : "Today"
        case 1: dayText = "Tomorrow"
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = calendar.locale ?? .current
            formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
            dayText = formatter.string(from: day)
        }
        return time.map { "\(dayText) · \($0)" } ?? dayText
    }

    /// "The Fillmore · 0.6 mi"
    static func placeLine(venueName: String?, city: String?, distanceMeters: Double?) -> String? {
        let name = venueName ?? city
        let distance = distanceMeters.map { meters -> String in
            let miles = meters / 1609.34
            return miles < 0.1 ? "nearby" : String(format: "%.1f mi", miles)
        }
        let parts = [name, distance].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "$25+", "Free", or nil when the price isn't known.
    static func priceText(min: Double?, currency: String?) -> String? {
        guard let min else { return nil }
        if min <= 0 { return "Free" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency ?? "USD"
        formatter.maximumFractionDigits = min.rounded() == min ? 0 : 2
        return formatter.string(from: NSNumber(value: min)).map { "\($0)+" }
    }

    private static func hour(_ localTime: String?) -> Int? {
        localTime.flatMap { $0.split(separator: ":").first }.flatMap { Int($0) }
    }

    private static func timeText(_ localTime: String?, calendar: Calendar) -> String? {
        guard let localTime else { return nil }
        let parts = localTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2,
              let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: parts[0], minute: parts[1])) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        // iOS puts a narrow no-break space before AM/PM; a plain one reads the same
        return formatter.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ")
    }
}
