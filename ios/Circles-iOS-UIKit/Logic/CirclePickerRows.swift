import Foundation

/// What the circle picker sheet shows (Wes, 2026-11-07: make it prettier,
/// it looked legacy). Pure, so the copy and the search rule are tested.
enum CirclePickerRows {
    /// A search field only earns its space once there are enough circles to hunt for
    static let searchThreshold = 8

    static func showsSearch(circleCount: Int) -> Bool {
        circleCount >= searchThreshold
    }

    /// "1 place · Private", "12 places · Public"
    static func detail(placeCount: Int, privacy: PrivacyLevel) -> String {
        let places = "\(placeCount) place\(placeCount == 1 ? "" : "s")"
        guard let tier = privacy.tier else { return places }
        return "\(places) · \(tier.title)"
    }

    static func filter(_ circles: [Circle], query: String) -> [Circle] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return circles }
        return circles.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
}
