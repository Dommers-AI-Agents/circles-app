import Foundation

/// The circle screen's category + tag chip rules. Pure; the controller
/// keeps the selections and the chip views.
enum CirclePlaceFilter {
    /// Tag chips for a circle: the `limit` most common distinct tags
    /// (case-insensitive, whitespace-trimmed, de-duped within a place so one
    /// place can't inflate a tag), most frequent first with an alphabetical
    /// tie-break, each shown in its first-seen raw spelling.
    static func tagChips(for places: [Place], limit: Int = 12) -> [String] {
        // Count tags case-insensitively, keeping the first-seen raw spelling
        var counts: [String: Int] = [:] // lowercased -> count
        var rawSpelling: [String: String] = [:] // lowercased -> raw value
        for place in places {
            guard let tags = place.tags else { continue }
            // De-dupe within a single place so one place can't inflate a tag
            let uniqueTags = Set(tags.map { $0.lowercased() })
            for lowered in uniqueTags {
                let trimmed = lowered.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                counts[trimmed, default: 0] += 1
                if rawSpelling[trimmed] == nil {
                    rawSpelling[trimmed] = tags.first { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == trimmed }
                }
            }
        }

        // Most common first, alphabetical tie-break; cap at `limit` chips
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .compactMap { rawSpelling[$0.key] }
    }

    /// The selected tag survives a chip rebuild only if it still exists
    /// (case-insensitively); otherwise the selection resets to All (nil).
    static func selectionAfterRebuild(selected: String?, chips: [String]) -> String? {
        if let selected = selected,
           !chips.contains(where: { $0.caseInsensitiveCompare(selected) == .orderedSame }) {
            return nil
        }
        return selected
    }

    /// Categories offered by the filter menu: every distinct category among
    /// the places, ordered by display name.
    static func categoryOptions(for places: [Place]) -> [PlaceCategory] {
        Set(places.map { $0.category }).sorted { $0.displayName < $1.displayName }
    }

    /// Places matching the selected category (exact) and tag
    /// (case-insensitive); nil means "All" for either.
    static func apply(_ places: [Place], category: PlaceCategory?, tag: String?) -> [Place] {
        places.filter { place in
            if let category = category, place.category != category {
                return false
            }
            if let tag = tag {
                let placeTags = place.tags ?? []
                guard placeTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else {
                    return false
                }
            }
            return true
        }
    }
}
