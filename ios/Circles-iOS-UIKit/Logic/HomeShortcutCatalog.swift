import Foundation

/// The Home Screen quick actions (long-press the app icon), chosen by the
/// user. iOS shows four; whatever slots the chosen actions leave free are
/// filled with "Check in at <nearby place>" rows by the check-in planner.
///
/// Pure: no UIKit. `QuickCheckInShortcuts` turns the result into
/// `UIApplicationShortcutItem`s and `QuickCheckInShortcutPlanner` maps a
/// tapped item back to a pending link.
struct HomeShortcutOption: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbolName: String
    /// The `pendingDeepLink` string a tap produces.
    let pendingLink: String
    /// The `UIApplicationShortcutItem.type` string.
    let shortcutType: String
}

enum HomeShortcutCatalog {
    /// iOS renders at most four quick actions.
    static let maxSelected = 4
    static let selectionKey = "homeShortcutSelection"
    static let widgetTypePrefix = "com.favcircles.circles.widget."

    /// What ships selected before the user touches the picker: the three
    /// original static items, in their original order.
    static let defaultSelection = ["check-in", "add-place", "postcard"]

    /// A widget's descriptor, as much as the catalog needs.
    struct Widget: Equatable {
        let id: String
        let title: String
        let symbolName: String
    }

    /// The fixed actions, then one "Open <widget>" per widget.
    static func options(widgets: [Widget]) -> [HomeShortcutOption] {
        var options: [HomeShortcutOption] = [
            HomeShortcutOption(id: "check-in", title: "Check In", subtitle: "Let your people know where you are",
                               symbolName: "figure.walk.arrival", pendingLink: "check-in", shortcutType: "com.favcircles.circles.check-in"),
            HomeShortcutOption(id: "add-place", title: "Add a Place", subtitle: "Save somewhere you love",
                               symbolName: "plus.circle", pendingLink: "add-place", shortcutType: "com.favcircles.circles.add-place")
        ]
        for widget in widgets {
            // The postcard keeps its original type so an icon menu rendered
            // by an older build still routes.
            let isPostcard = widget.id == "postcard"
            options.append(HomeShortcutOption(
                id: isPostcard ? "postcard" : "widget:\(widget.id)",
                title: isPostcard ? "Send a Postcard" : widget.title,
                subtitle: isPostcard ? "A photo, a note, mailed or shared" : "Open the \(widget.title) widget",
                symbolName: isPostcard ? "envelope" : widget.symbolName,
                pendingLink: "widget:\(widget.id)",
                shortcutType: isPostcard ? "com.favcircles.circles.postcard" : widgetTypePrefix + widget.id
            ))
        }
        return options
    }

    /// The saved selection, in order, dropping ids that no longer exist and
    /// anything past the cap. `nil` stored means the defaults.
    static func selection(stored: [String]?, options: [HomeShortcutOption]) -> [HomeShortcutOption] {
        let ids = stored ?? defaultSelection
        var seen = Set<String>()
        return ids.compactMap { id in
            guard !seen.contains(id), let option = options.first(where: { $0.id == id }) else { return nil }
            seen.insert(id)
            return option
        }
        .prefix(maxSelected)
        .map { $0 }
    }

    /// Toggling an id in the picker; refuses a fifth selection.
    static func toggled(_ id: String, in selection: [String]) -> [String] {
        if let index = selection.firstIndex(of: id) {
            var next = selection
            next.remove(at: index)
            return next
        }
        guard selection.count < maxSelected else { return selection }
        return selection + [id]
    }

    /// Slots left for nearby check-in rows.
    static func nearbySlots(selectedCount: Int) -> Int {
        max(0, maxSelected - selectedCount)
    }

    /// The pending link for a tapped item of one of the catalog's types.
    static func pendingLink(forShortcutType type: String) -> String? {
        switch type {
        case "com.favcircles.circles.check-in": return "check-in"
        case "com.favcircles.circles.add-place": return "add-place"
        case "com.favcircles.circles.postcard": return "widget:postcard"
        default:
            guard type.hasPrefix(widgetTypePrefix) else { return nil }
            let id = String(type.dropFirst(widgetTypePrefix.count))
            return id.isEmpty ? nil : "widget:\(id)"
        }
    }
}
