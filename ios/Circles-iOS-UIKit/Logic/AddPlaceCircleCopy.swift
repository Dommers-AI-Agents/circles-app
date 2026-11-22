import Foundation

/// The Circle card on Add Place and the Save button under it (Wes, 2026-11-09:
/// find the place first, then say where it lives). Pure.
enum AddPlaceCircleCopy {

    /// Card title: the circle's name, or the question
    static func title(circleName: String?) -> String {
        circleName ?? "Where should this place live?"
    }

    /// Card subtitle: the circle's detail line, "the one you used last", or the nudge
    static func subtitle(circleDetail: String?, remembered: Bool) -> String {
        guard let circleDetail else { return "Choose a circle — the list it will live in" }
        return remembered ? "\(circleDetail) · the one you used last, tap to change" : circleDetail
    }

    /// Section label above the card
    static func sectionLabel(remembered: Bool) -> String {
        remembered ? "Circle · the one you used last" : "Circle · a list of places"
    }

    /// The Save button: "Save to Charlotte NC", or the step still missing
    static func saveTitle(circleName: String?) -> String {
        guard let circleName, !circleName.isEmpty else { return "Choose a circle (a list) to save" }
        let trimmed = circleName.count > 22 ? String(circleName.prefix(21)).trimmingCharacters(in: .whitespaces) + "…" : circleName
        return "Save to \(trimmed)"
    }
}

/// Which circle Add Place starts on when the caller didn't name one (Home's
/// Add Place button, a place tapped on the map). Wes, 2026-11-21: "The circle
/// should default to the last circle selected". The card says "the one you
/// used last" so the choice is never silent. Pure.
enum AddPlaceDefaultCircle {
    /// The circle saved into last, when it still exists; the only circle when
    /// there's one; otherwise none (the card asks).
    static func pick(from circleIds: [String], lastUsedId: String?) -> String? {
        if let lastUsedId, circleIds.contains(lastUsedId) { return lastUsedId }
        return circleIds.count == 1 ? circleIds[0] : nil
    }
}
