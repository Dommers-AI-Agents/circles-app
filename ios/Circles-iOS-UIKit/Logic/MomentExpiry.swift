import Foundation

/// Disappearing moments (Wes, 2026-10-18): posted with "Disappears after 24
/// hours", a moment carries `expiresAt` and is deleted for good once it
/// passes. Pure: what's gone, and the "5h left" countdown shown on it.
enum MomentExpiry {
    static let lifetime: TimeInterval = 24 * 60 * 60

    /// Ran out (never true for an ordinary moment)
    static func isExpired(_ expiresAt: Date?, now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    /// "23h left", "45m left", "<1m left"; nil for an ordinary or gone moment
    static func timeLeft(_ expiresAt: Date?, now: Date = Date()) -> String? {
        guard let expiresAt, expiresAt > now else { return nil }
        let minutes = Int(expiresAt.timeIntervalSince(now) / 60)
        if minutes >= 60 { return "\(minutes / 60)h left" }
        if minutes >= 1 { return "\(minutes)m left" }
        return "<1m left"
    }

    /// The badge: "⏱ 5h left"
    static func badge(_ expiresAt: Date?, now: Date = Date()) -> String? {
        timeLeft(expiresAt, now: now).map { "\u{23F1} \($0)" }
    }

    /// A list without the ones that ran out (cached lists can outlive them)
    static func visible(_ moments: [PlaceVideo], now: Date = Date()) -> [PlaceVideo] {
        moments.filter { !isExpired($0.expiresAt, now: now) }
    }
}
