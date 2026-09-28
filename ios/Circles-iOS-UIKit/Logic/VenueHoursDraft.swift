import Foundation

/// A full week of opening hours as the owner edits it, and the exact body
/// PATCH /rewards/venues/:id/place expects. The server REPLACES the stored
/// week, so the body always carries all seven days.
struct VenueHoursDraft: Equatable {

    struct Day: Equatable {
        /// 0 = Sunday … 6 = Saturday (the server's and OpeningHour's numbering)
        let day: Int
        var isClosed: Bool
        /// 24-hour "HH:MM"
        var open: String
        var close: String
    }

    static let defaultOpen = "09:00"
    static let defaultClose = "17:00"

    var days: [Day]

    /// Monday first, the way a shop owner reads a week
    static let displayOrder = [1, 2, 3, 4, 5, 6, 0]

    /// English day names — the app's copy is English, and a bare Calendar's
    /// symbols follow whatever locale the device (or test host) runs in
    static func dayName(_ day: Int) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][(day % 7 + 7) % 7]
    }

    /// Seeds the editor from whatever the place already has. Days the record
    /// doesn't mention start open 9–5 so the owner edits rather than types.
    init(existing: [(day: Int, open: String?, close: String?, isClosed: Bool?)]) {
        days = Self.displayOrder.map { day in
            guard let known = existing.first(where: { $0.day == day }) else {
                return Day(day: day, isClosed: false, open: Self.defaultOpen, close: Self.defaultClose)
            }
            let open = Self.normalized(known.open)
            let close = Self.normalized(known.close)
            let closed = known.isClosed == true || open == nil || close == nil
            return Day(day: day, isClosed: closed, open: open ?? Self.defaultOpen, close: close ?? Self.defaultClose)
        }
    }

    init(hours: [OpeningHour]?) {
        self.init(existing: (hours ?? []).map { ($0.day, $0.open, $0.close, $0.isClosed) })
    }

    /// Why the week can't be saved yet, or nil when it can.
    var problem: String? {
        if days.allSatisfy(\.isClosed) {
            return "Every day is marked closed. Open at least one day, or leave your hours as they are."
        }
        if let same = days.first(where: { !$0.isClosed && $0.open == $0.close }) {
            return "\(Self.dayName(same.day)) opens and closes at the same time."
        }
        return nil
    }

    /// Request body: `openingHours` sorted Sunday-first, closed days with null times
    var requestBody: [String: Any] {
        let week: [[String: Any]] = days.sorted { $0.day < $1.day }.map { day in
            [
                "day": day.day,
                "isClosed": day.isClosed,
                "open": day.isClosed ? NSNull() : day.open,
                "close": day.isClosed ? NSNull() : day.close
            ]
        }
        return ["openingHours": week]
    }

    /// "9" / "09:00" / "9:00" → "09:00"; nil for anything else
    static func normalized(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    /// "09:00" → date today at that time, for a time picker
    static func date(from hhmm: String, calendar: Calendar = .current) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        let start = calendar.startOfDay(for: Date())
        guard parts.count == 2 else { return start }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: start) ?? start
    }

    static func hhmm(from date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
