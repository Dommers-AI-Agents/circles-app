import Foundation

/// The words on Get Rewards about the customer's own history at a store
/// (Wes, 2026-11-02: "use the empty space to add value"). Pure.
enum StoreRewardsCopy {

    /// "+25" / "−100" for a history row
    static func signedPoints(_ points: Int) -> String {
        points >= 0 ? "+\(points)" : "\u{2212}\(abs(points))"
    }

    /// A history row's subtitle: what happened to a reward ticket, else nothing
    static func rowNote(kind: String) -> String? {
        switch kind {
        case "expired": return "Ran out before it was given · points came back"
        case "redeem": return "Reward used"
        default: return nil
        }
    }

    /// "Today" / "Yesterday" / "3 days ago" / "Oct 12"
    static func when(_ iso: String?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let date = parse(iso) else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return "\(days) days ago"
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, equalTo: now, toGranularity: .year) ? "MMMd" : "MMMdyyyy")
            return formatter.string(from: date)
        }
    }

    /// The line under the stats: "Last visit yesterday" / "First visit? Scan at the register to start"
    static func lastVisitLine(_ history: VenueRewardHistory, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let when = when(history.lastVisitAt, now: now, calendar: calendar) else {
            return "No visits yet. Scan the QR code at the register to start."
        }
        // "today" / "3 days ago" read lowercase mid-sentence; a date keeps its capital
        let relative = when == "Today" || when == "Yesterday" || when.hasSuffix(" ago")
        return "Last visit \(relative ? when.lowercased() : when)"
    }

    /// A store with no rewards posted: the points are still worth something
    static func noOffersLine(venueName: String, balance: Int) -> String {
        balance > 0
            ? "\(venueName) hasn't posted rewards yet. Your \(balance) \(balance == 1 ? "point stays" : "points stay") saved here for when they do."
            : "\(venueName) hasn't posted rewards yet. Points you earn now stay saved for when they do."
    }

    private static func parse(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)
    }
}
