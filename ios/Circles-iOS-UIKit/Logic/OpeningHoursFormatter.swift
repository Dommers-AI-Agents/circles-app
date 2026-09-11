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
