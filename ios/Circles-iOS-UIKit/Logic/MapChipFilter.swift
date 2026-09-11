import Foundation

/// The full-screen map's content filters, applied after the people scope:
/// the My Places origin sub-filter, the category-group chip, the region
/// chip, and the search text. Pure so the home page's list beside the map
/// can run through the exact same rules the pins use.
enum MapChipFilter {
    struct Context {
        var group: PlaceCategoryGroup = .all
        var regionId: String?
        var regionGroups: [RegionGroup] = []
        /// nil = all my places, "in_app" = added in the app, otherwise an
        /// importSource value ("google_maps").
        var importOrigin: String?
    }

    /// Origin, then category group, then region — in that order.
    static func apply(_ list: [Place], context: Context) -> [Place] {
        var result = applyOrigin(list, origin: context.importOrigin)
        if context.group != .all {
            result = result.filter { context.group.matches($0.category.rawValue) }
        }
        if let regionId = context.regionId,
           let region = context.regionGroups.first(where: { $0.id == regionId }) {
            result = result.filter { region.contains($0) }
        }
        return result
    }

    /// The My Places origin sub-filter (no-op when none selected).
    static func applyOrigin(_ list: [Place], origin: String?) -> [Place] {
        guard let origin = origin else { return list }
        return list.filter { origin == "in_app" ? $0.importSource == nil : $0.importSource == origin }
    }

    /// Search text over name/address/notes (no-op when nil).
    static func applySearch(_ list: [Place], query: String?) -> [Place] {
        guard let query = query else { return list }
        return list.filter { $0.matches(searchQuery: query) }
    }

    /// Trimmed query, or nil when there's nothing left to search for.
    static func normalizedQuery(_ query: String?) -> String? {
        let normalized = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (normalized?.isEmpty ?? true) ? nil : normalized
    }

    /// Display name for an origin row: the source itself ("FavCircles",
    /// "Google Places") — the menu marks these as sub-rows of My Places.
    static func originTitle(_ origin: String) -> String {
        switch origin {
        case "in_app": return "FavCircles"
        case "google_maps": return "Google Places"
        case "mapstr": return "Mapstr"
        case "swarm": return "Swarm"
        default: return origin.capitalized
        }
    }
}
