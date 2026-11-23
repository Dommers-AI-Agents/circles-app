import Foundation

/// What a chat shows, top to bottom (2026-11-23): day dividers between
/// days, and messages from one person in quick succession drawn as one run
/// (name once at the top, avatar and time once at the bottom). Pure, so the
/// rules are table-tested; the chat screen only draws the rows.
enum ChatTimeline {

    /// The parts of a message the rules need
    struct Entry: Equatable {
        let id: String
        let senderId: String
        let date: Date?
        let isMine: Bool
        /// The other person in a one-on-one chat has read it
        var readByOther: Bool = false
    }

    struct Bubble: Equatable {
        let id: String
        /// First of its run: the sender's name goes here in a group chat
        let startsRun: Bool
        /// Last of its run: the avatar, the time and the bubble's tail go here
        let endsRun: Bool
    }

    enum Row: Equatable {
        case day(String)
        case message(Bubble)

        var messageId: String? {
            if case .message(let bubble) = self { return bubble.id }
            return nil
        }
    }

    /// Longer than this between two messages from one person starts a new run
    static let runGap: TimeInterval = 5 * 60

    /// `entries` oldest first. `grouped` off is the classic chat: one row
    /// per message, each its own run, no day dividers.
    static func rows(_ entries: [Entry], grouped: Bool, calendar: Calendar = .current, now: Date = Date()) -> [Row] {
        guard grouped else {
            return entries.map { .message(Bubble(id: $0.id, startsRun: true, endsRun: true)) }
        }
        var rows: [Row] = []
        for (index, entry) in entries.enumerated() {
            let previous = index > 0 ? entries[index - 1] : nil
            let next = index + 1 < entries.count ? entries[index + 1] : nil
            if let date = entry.date, !sameDay(previous?.date, date, calendar) {
                rows.append(.day(dayTitle(for: date, calendar: calendar, now: now)))
            }
            rows.append(.message(Bubble(id: entry.id,
                                        startsRun: !continuesRun(previous, entry, calendar),
                                        endsRun: !continuesRun(entry, next, calendar))))
        }
        return rows
    }

    /// "Read" or "Sent" under your newest message in a one-on-one
    /// chat, and only while it is the last thing said: (message id, word).
    static func receipt(_ entries: [Entry]) -> (id: String, text: String)? {
        guard let last = entries.last, last.isMine else { return nil }
        return (last.id, last.readByOther ? "Read" : "Sent")
    }

    /// "Today", "Yesterday", the weekday within the last week, then the date
    static func dayTitle(for date: Date, calendar: Calendar = .current, now: Date = Date(),
                         locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? Int.max
        if days > 0 && days < 7 {
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        }
        return formatter.string(from: date)
    }

    private static func sameDay(_ a: Date?, _ b: Date, _ calendar: Calendar) -> Bool {
        guard let a else { return false }
        return calendar.isDate(a, inSameDayAs: b)
    }

    /// `b` follows `a` in one run: same person, same day, close in time
    private static func continuesRun(_ a: Entry?, _ b: Entry?, _ calendar: Calendar) -> Bool {
        guard let a, let b, a.senderId == b.senderId else { return false }
        guard let first = a.date, let second = b.date else { return true }
        return calendar.isDate(first, inSameDayAs: second) && abs(second.timeIntervalSince(first)) <= runGap
    }
}
