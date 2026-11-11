import Foundation

/// Scan Action links (2026-11-11): `https://api.favcircles.com/q/<code>`.
/// A code is 8 easy-to-read characters (no 0/O, 1/I/L) for a QR someone
/// made, or a guide's name (`share-a-place`) for a fixed "show me how" QR.
/// Pure; the server (services/scanActionService.js) uses the same rules.
enum ScanActionLink {
    static let host = "api.favcircles.com"
    private static let alphabet = Set("23456789ABCDEFGHJKMNPQRSTUVWXYZ")
    /// What the pasteboard holds after "Get FavCircles" on the web page
    static let pasteboardPrefix = "favcircles-scan:"

    /// A code as scanned or typed → its canonical form, or nil
    static func code(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = text.uppercased()
        if upper.count == 8, upper.allSatisfy({ alphabet.contains($0) }) { return upper }
        let lower = text.lowercased()
        // Guide names are letters and hyphens only, so a mistyped code (a 0 for
        // an O) is never read as one
        let slug = lower.range(of: "^[a-z][a-z-]{2,39}$", options: .regularExpression) != nil
        return slug && !lower.hasSuffix("-") ? lower : nil
    }

    static func url(code: String) -> URL {
        URL(string: "https://\(host)/q/\(code)")!
    }

    /// The code on the pasteboard the web page left, if any
    static func code(fromPasteboard text: String?) -> String? {
        guard let text, text.hasPrefix(pasteboardPrefix) else { return nil }
        return code(String(text.dropFirst(pasteboardPrefix.count)))
    }
}
