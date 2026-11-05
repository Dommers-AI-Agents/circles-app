import Foundation

/// What a sticker the owner held to the phone turned out to be, for Manage
/// Store → NFC stickers → Check a sticker. Pure: the link shape is
/// `DeepLinkRouter`'s, the same parser that opens a tapped sticker.
enum NFCStickerMatch: Equatable {
    /// One of this store's stickers, by tag
    case sticker(tag: String)
    /// This store's window link with a tag the store no longer has (removed):
    /// it still opens the store, taps aren't counted
    case removedTag(String)
    /// This store's window link with no tag: opens the store, not counted
    case windowLink
    /// Another FavCircles store's code
    case otherStore
    /// Not a FavCircles store link at all
    case other
}

enum NFCStickerLink {

    static func match(_ link: String, windowUrl: String?, registerUrl: String? = nil, knownTags: Set<String>,
                      router: DeepLinkRouter = DeepLinkRouter()) -> NFCStickerMatch {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil,
              case .sticker(let code, let tag)? = router.destination(for: url) else { return .other }
        // This store's window link, or its register link (register stickers)
        let ownCodes = [windowUrl, registerUrl].compactMap { $0.flatMap(URL.init(string:)) }.compactMap { link -> String? in
            if case .sticker(let own, _)? = router.destination(for: link) { return own }
            return nil
        }
        guard ownCodes.contains(where: { code.caseInsensitiveCompare($0) == .orderedSame }) else { return .otherStore }
        guard let tag, !tag.isEmpty else { return .windowLink }
        return knownTags.contains(tag) ? .sticker(tag: tag) : .removedTag(tag)
    }

    /// "12 taps · last today" under a sticker's name
    static func tapsLine(taps: Int, lastTap: Date?, written: Bool, locked: Bool,
                         now: Date = Date(), calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if !written {
            parts.append("Not written yet")
        } else {
            parts.append(taps == 1 ? "1 tap" : "\(taps) taps")
            if let lastTap { parts.append("last \(dayPhrase(lastTap, now: now, calendar: calendar))") }
        }
        if locked { parts.append("locked") }
        return parts.joined(separator: " \u{00B7} ")
    }

    static func dayPhrase(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2..<7: return "\(days) days ago"
        default:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return formatter.string(from: date)
        }
    }
}
