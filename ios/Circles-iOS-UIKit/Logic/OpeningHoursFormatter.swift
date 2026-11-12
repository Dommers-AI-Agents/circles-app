import Foundation

/// The place page's one-line hours summary for today: "Closed today",
/// "Open 24 hours", "Open today: 9 AM - 5:30 PM", a legacy free-text
/// string, or "Hours not available".
enum OpeningHoursFormatter {
    /// `today` is 0 for Sunday, 1 for Monday, … (Calendar weekday minus one).
    static func todaySummary(_ hours: [OpeningHour], today: Int = todayIndex()) -> String {
        // Find today's hours
        if let todayHours = hours.first(where: { $0.day == today }) {
            var hoursText = ""

            // Check if it's closed
            if todayHours.isClosed == true || (todayHours.open == "00:00" && todayHours.close == "00:00") {
                hoursText = "Closed today"
            } else if todayHours.open == "00:00" && todayHours.close == "23:59" {
                hoursText = "Open 24 hours"
            } else if let open = todayHours.open, let close = todayHours.close {
                // Format the hours
                hoursText = "Open today: \(time(open)) - \(time(close))"
            } else if let hoursString = todayHours.hours {
                // Fallback to legacy hours string
                hoursText = hoursString
            }

            return hoursText
        }

        return "Hours not available"
    }

    /// The whole week on one line, days with the same hours grouped:
    /// "Sat 8 AM–1 PM", "Mon, Tue 9 AM–5 PM · Sat 10 AM–2 PM" (the server's
    /// market line, marketDetails.hoursFrom). nil when nothing is known.
    static func weekSummary(_ hours: [OpeningHour]) -> String? {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var order: [String] = []
        var days: [String: Set<Int>] = [:]
        for row in hours where row.isClosed != true && (0...6).contains(row.day) {
            let label: String
            if let open = row.open, let close = row.close {
                if open == "00:00" && close == "23:59" { label = "open 24 hours" } else { label = "\(time(open))–\(time(close))" }
            } else if let open = row.open {
                label = "from \(time(open))"
            } else if let legacy = row.hours, !legacy.isEmpty {
                label = legacy
            } else {
                continue
            }
            if days[label] == nil { order.append(label) }
            days[label, default: []].insert(row.day)
        }
        guard !order.isEmpty else { return nil }
        if order.count == 1, order[0] == "open 24 hours", days[order[0]]?.count == 7 { return "Open 24 hours" }
        return order.map { label in
            (days[label] ?? []).sorted().map { dayNames[$0] }.joined(separator: ", ") + " " + label
        }.joined(separator: " · ")
    }

    static func todayIndex(calendar: Calendar = .current, now: Date = Date()) -> Int {
        calendar.component(.weekday, from: now) - 1 // 0 for Sunday, 1 for Monday, etc.
    }

    /// "14:05" → "2:05 PM", "09:00" → "9 AM"; anything unparseable comes back as-is.
    static func time(_ time: String) -> String {
        // Convert 24-hour format to 12-hour format
        let components = time.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            return time
        }

        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)

        if minute == 0 {
            return "\(displayHour) \(period)"
        } else {
            return String(format: "%d:%02d %@", displayHour, minute, period)
        }
    }
}
