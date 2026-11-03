import Foundation

/// The words for one row of the store's Activity list. Pure.
/// Every register scan is listed with its time to the second (Wes,
/// 2026-11-03), including scans that earned nothing, so the team can check
/// them against their security cameras.
enum VenueActivityCopy {

    /// Scans that earned nothing (server: services/scanAttempts) — listed,
    /// but left out of the busiest hours/days charts.
    static let attemptTypes: Set<String> = ["scan_far", "scan_repeat", "scan_removed"]

    /// What the customer did, and the row's SF Symbol.
    static func verb(type: String, location: String?, offerTitle: String?) -> (text: String, icon: String) {
        switch type {
        case "venue_visit":
            // Location off still earns (honor system); the owner sees it.
            // "unknown" = the phone sent no location (an older app version).
            switch location {
            case "off": return ("bought something (register scan, location off)", "location.slash")
            case "unknown": return ("bought something (register scan, location not checked)", "qrcode.viewfinder")
            default: return ("bought something (register scan)", "qrcode.viewfinder")
            }
        case "scan_far": return ("scanned your register code from far away (no points)", "location.slash.fill")
        case "scan_repeat": return ("scanned your register code again today (no points)", "arrow.clockwise")
        case "scan_removed": return ("scanned your register code, removed from your rewards (no points)", "person.crop.circle.badge.xmark")
        case "sticker_signup": return ("joined from your sticker", "person.badge.plus")
        case "sticker_save": return ("saved your place", "bookmark.fill")
        case "redemption":
            return ("redeemed a reward\(offerTitle.map { " — \($0)" } ?? "")", "gift.fill")
        case "code_redemption": return ("redeemed a code", "number.square.fill")
        case "redemption_refund":
            return ("got points back, reward not given in time\(offerTitle.map { " (\($0))" } ?? "")", "arrow.uturn.backward.circle")
        case "share_conversion": return ("brought a friend", "person.2.fill")
        default: return (type.replacingOccurrences(of: "_", with: " "), "sparkles")
        }
    }

    /// "Nov 3, 2026 at 6:26:51 AM" — seconds, to match camera footage.
    static func time(_ date: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
