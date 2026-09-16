import Foundation

/// One entry of a saver's rating history on a place ("latest wins, history
/// kept"). `checkInId` is set when a check-in prompted the re-rate.
struct RatingHistoryEntry: Codable, Equatable {
    let rating: Int
    let at: Date?
    let checkInId: String?
}

/// Wording for the place page's "★ Your rating" line. Pure — no UIKit.
enum RatingHistoryFormatter {
    /// "9/10", or with a real history "9/10 · was 7 (3 ratings)"; a history
    /// that never moved reads "9/10 (3 ratings)". nil when unrated.
    static func summary(current: Int?, history: [RatingHistoryEntry]?) -> String? {
        guard let current = current else { return nil }
        let entries = history ?? []
        guard entries.count >= 2, let first = entries.first else { return "\(current)/10" }
        let count = "(\(entries.count) ratings)"
        if first.rating == current { return "\(current)/10 \(count)" }
        return "\(current)/10 · was \(first.rating) \(count)"
    }

    /// Shown in place of a score when the viewer saved the place but never
    /// rated it. Tapping it opens the rating sheet.
    static let nudge = "★ Been here? Rate it"

    /// Subtitle for the post-check-in prompt.
    static func recheckSubtitle(current: Int?) -> String {
        guard let current = current else { return "Tap a rating, or skip" }
        return "Your rating so far: \(current)/10 — tap to update, or skip to keep it"
    }

    /// A rating given this recently is still fresh: no re-rate prompt when a
    /// check-in follows a save by minutes (the post-save check-in offer).
    static let freshRatingWindow: TimeInterval = 2 * 60 * 60

    static func shouldPromptAfterCheckIn(userRatedAt: Date?, now: Date = Date()) -> Bool {
        guard let ratedAt = userRatedAt else { return true }
        return now.timeIntervalSince(ratedAt) > freshRatingWindow
    }
}
