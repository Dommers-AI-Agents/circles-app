import Foundation

/// The words for a reward ticket in the customer's "Rewards used" list
/// (2026-11-01). Pure.
enum RewardTicketCopy {

    struct Line: Equatable {
        let text: String
        let symbol: String
        /// Still open: tapping shows it to staff
        let isOpen: Bool
    }

    /// The tickets worth a row: the ones still open and the ones staff gave.
    /// A ticket that ran out came back as points, so it says nothing worth
    /// the space (Wes, 2026-11-02).
    static func shown(_ tickets: [RewardVoucher]) -> [RewardVoucher] {
        tickets.filter { $0.status != "expired" }
    }

    static func historyLine(_ ticket: RewardVoucher, calendar: Calendar = .current, now: Date = Date()) -> Line {
        let what = "\(ticket.offerTitle) at \(ticket.venueName)"
        switch ticket.status {
        case "given":
            let when = date(ticket.givenAt).map { " " + dayAndTime($0, calendar: calendar, now: now) } ?? ""
            return Line(text: "\(what) \u{00B7} Given\(when)", symbol: "checkmark.circle.fill", isOpen: false)
        case "expired":
            return Line(text: "\(what) \u{00B7} Not used, \(ticket.pointsCost) points back", symbol: "arrow.uturn.backward.circle.fill", isOpen: false)
        default:
            return Line(text: "\(what) \u{00B7} Ready, tap to show staff", symbol: "ticket.fill", isOpen: true)
        }
    }

    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    /// "today 5:54 PM", "yesterday 9:10 AM", "Oct 28"
    static func dayAndTime(_ date: Date, calendar: Calendar, now: Date) -> String {
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateStyle = .none
        time.timeStyle = .short
        if calendar.isDate(date, inSameDayAs: now) { return "today \(time.string(from: date))" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday \(time.string(from: date))"
        }
        let day = DateFormatter()
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.setLocalizedDateFormatFromTemplate("MMMd")
        return day.string(from: date)
    }
}
