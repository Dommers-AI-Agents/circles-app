import Foundation

/// Wording for a store's waitlist, guest side and host side. Pure.
enum WaitlistCopy {

    static let quoteOptions = [5, 10, 15, 20, 30, 45, 60, 90]

    // MARK: Guest

    /// "You're #3 in line · about 40 min"; called: "Your table is ready — head to the host stand"
    static func statusLine(_ entry: WaitlistEntry) -> String {
        if entry.isCalled { return "Your table is ready — head to the host stand" }
        let place = entry.position.map { "You're #\($0) in line" } ?? "You're in line"
        guard let minutes = entry.estimateMinutes else { return place }
        return "\(place) · about \(minutes) min"
    }

    static func partyLine(_ size: Int) -> String { size == 1 ? "Party of 1" : "Party of \(size)" }

    static func joinTitle(storeName: String) -> String { "Join the line at \(storeName)" }

    static func joinExplanation(quoteMinutes: Int) -> String {
        "The host quotes about \(quoteMinutes) minutes per party ahead of you. We'll notify your phone when your table is ready — no need to wait by the door."
    }

    static let joinButton = "Join the line"
    static let leaveButton = "Leave the line"
    static let calledFooter = "They'll hold it for 15 minutes."

    /// The place page row for an open entry
    static func placeRow(_ entry: WaitlistEntry) -> String {
        entry.isCalled ? "Your table is ready" : statusLine(entry)
    }

    // MARK: Host

    /// "Ana · party of 2 · 12 min"; called: "Ana · party of 2 · called 3 min ago"
    static func hostRow(_ entry: WaitlistEntry, now: Date = Date()) -> String {
        var parts = [entry.name ?? "Guest", entry.partySize == 1 ? "party of 1" : "party of \(entry.partySize)"]
        if entry.isCalled, let called = entry.notifiedAt.flatMap(parseISO) {
            parts.append("called \(minutesText(since: called, now: now))")
        } else if let joined = entry.joinedAt.flatMap(parseISO) {
            parts.append("waiting \(minutesText(since: joined, now: now))")
        }
        return parts.joined(separator: " · ")
    }

    static func minutesText(since date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        return minutes == 0 ? "just now" : "\(minutes) min"
    }

    static func lineHeader(count: Int) -> String {
        switch count {
        case 0: return "Nobody is waiting"
        case 1: return "1 party waiting"
        default: return "\(count) parties waiting"
        }
    }

    static func settingsFooter(enabled: Bool, quoteMinutes: Int) -> String {
        enabled
            ? "Customers join from your window sticker, your place page or your web page, see their place in line, and get a notification when you tap Notify. The quote is \(quoteMinutes) minutes per party ahead."
            : "Off. Turn it on and customers can join the line from your window sticker or your place page instead of waiting at the door."
    }

    /// Manage Store row subtitle
    static func rowSummary(enabled: Bool, waiting: Int) -> String {
        guard enabled else { return "Off: let customers join the line from your window sticker" }
        return waiting == 0 ? "On · nobody waiting" : "On · \(lineHeader(count: waiting))"
    }

    private static func parseISO(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}
