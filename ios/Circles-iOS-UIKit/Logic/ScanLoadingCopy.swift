import Foundation

/// The bubble while a scanned code is being redeemed. It says what the scan
/// is for, not "Checking rewards" for everything (Wes, 2026-11-12): a window
/// sticker ("Love it here? Save us.") sets you up to save the store, the
/// JOINUS card sets you up to join, and only a register card is about
/// rewards. The kind and name come from the quick code lookup; until it
/// answers, the words commit to nothing.
enum ScanLoadingCopy {
    static let initial = "Setting you up\u{2026}"

    /// `kind`: "window" | "register" | "generic" (nil while unknown)
    static func message(kind: String?, name: String?) -> String {
        let store = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = (store?.isEmpty == false) ? store : nil
        switch kind {
        case "generic":
            return "Setting you up to join\u{2026}"
        case "window":
            return named.map { "Setting you up to save \($0)\u{2026}" } ?? "Setting you up to save this place\u{2026}"
        case "register":
            return named.map { "Checking rewards at \($0)\u{2026}" } ?? "Checking rewards\u{2026}"
        default:
            return named.map { "Setting you up at \($0)\u{2026}" } ?? initial
        }
    }
}
