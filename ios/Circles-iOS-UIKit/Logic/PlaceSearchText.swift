import Foundation

/// The text a search query is matched against, and which parts of it may be
/// matched loosely.
///
/// Two lessons from a real miss. "Deli" found nothing because the category a
/// place was filed under was never part of the text — only its name, address
/// and notes were. And it found the wrong things, because typo tolerance ran
/// over the address too: "deli" is one edit from the "dela" in "Delaware
/// Ave", so a Belmar street outranked a Charlotte deli. So: category words
/// are IN, and only the name and those words may be matched fuzzily; the
/// address and notes match exactly or not at all.
enum PlaceSearchText {
    /// Tags the app stamps on every import. Matching "google" against every
    /// imported place is noise, not a search.
    static let systemTags: Set<String> = ["google-import", "default-list"]

    /// Everything the exact (substring) paths look at.
    static func exactText(for place: Place) -> String {
        fold(([place.name, place.address, place.description ?? "", place.notes ?? "",
               place.publicNotes ?? "", place.privateNotes ?? ""] + categoryWords(for: place))
            .joined(separator: " "))
    }

    /// The text a query word may be one typo away from: the name and the
    /// category vocabulary. Never the address.
    static func fuzzText(for place: Place) -> String {
        fold(([place.name] + categoryWords(for: place)).joined(separator: " "))
    }

    /// The words a person would use for what this place is: its category and
    /// the group it sits in ("Restaurant", "Food"), its subcategory, a custom
    /// category's name, and the person's own tags with the hyphens opened up.
    static func categoryWords(for place: Place) -> [String] {
        var words: [String] = [place.category.displayName, PlaceCategoryGroup.group(for: place.category.rawValue).title]
        if let sub = place.subcategory, !sub.isEmpty { words.append(sub) }
        if place.category == .other, let custom = place.customCategoryId, !custom.isEmpty { words.append(custom) }
        for tag in place.tags ?? [] where !systemTags.contains(tag) {
            words.append(tag.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " "))
        }
        return words
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// Both texts for a place, built once and reused until the place's
    /// searchable fields change. Building them (joins + locale folding) for
    /// every place on every keystroke was most of the cost of a search pass,
    /// and the map's pin filter did it all again a beat later.
    static func texts(for place: Place) -> (exact: String, fuzz: String) {
        PlaceSearchTextCache.shared.texts(for: place)
    }
}

/// Memo of `PlaceSearchText` per place id, checked against a fingerprint of
/// every field that feeds it — an edited name or new tag rebuilds that one
/// entry. Thread-safe; cleared wholesale if it ever outgrows `limit`.
final class PlaceSearchTextCache {
    static let shared = PlaceSearchTextCache()

    private struct Entry { let fingerprint: Int; let exact: String; let fuzz: String }
    private var entries: [String: Entry] = [:]
    private let lock = NSLock()
    let limit: Int

    init(limit: Int = 20_000) { self.limit = limit }

    static func fingerprint(of place: Place) -> Int {
        var h = Hasher()
        h.combine(place.name)
        h.combine(place.address)
        h.combine(place.description)
        h.combine(place.notes)
        h.combine(place.publicNotes)
        h.combine(place.privateNotes)
        h.combine(place.category.rawValue)
        h.combine(place.subcategory)
        h.combine(place.customCategoryId)
        h.combine(place.tags)
        return h.finalize()
    }

    func texts(for place: Place) -> (exact: String, fuzz: String) {
        let fingerprint = Self.fingerprint(of: place)
        lock.lock()
        if let hit = entries[place.id], hit.fingerprint == fingerprint {
            lock.unlock()
            return (hit.exact, hit.fuzz)
        }
        lock.unlock()
        let exact = PlaceSearchText.exactText(for: place)
        let fuzz = PlaceSearchText.fuzzText(for: place)
        lock.lock()
        if entries.count >= limit { entries.removeAll(keepingCapacity: true) }
        entries[place.id] = Entry(fingerprint: fingerprint, exact: exact, fuzz: fuzz)
        lock.unlock()
        return (exact, fuzz)
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
    func removeAll() { lock.lock(); entries.removeAll(); lock.unlock() }
}
