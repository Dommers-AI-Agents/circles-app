import Testing
@testable import Circles_iOS

/// User-chosen Home Screen quick actions: the catalog, the saved selection,
/// the four-slot cap, and tapped items back into pending links.
struct HomeShortcutCatalogTests {
    private let widgets = [
        HomeShortcutCatalog.Widget(id: "water", title: "Water", symbolName: "drop.fill"),
        HomeShortcutCatalog.Widget(id: "postcard", title: "Postcard", symbolName: "envelope.open.fill"),
        HomeShortcutCatalog.Widget(id: "sleepsounds", title: "Sleep Sounds", symbolName: "moon.zzz.fill")
    ]

    @Test func catalogKeepsTheOriginalThreeTypesAndAddsWidgets() {
        let options = HomeShortcutCatalog.options(widgets: widgets)
        #expect(options.map(\.id) == ["check-in", "add-place", "widget:water", "postcard", "widget:sleepsounds"])
        #expect(options.first { $0.id == "postcard" }?.shortcutType == "com.favcircles.circles.postcard")
        #expect(options.first { $0.id == "widget:sleepsounds" }?.shortcutType == "com.favcircles.circles.widget.sleepsounds")
        #expect(options.first { $0.id == "widget:sleepsounds" }?.pendingLink == "widget:sleepsounds")
    }

    @Test func defaultSelectionIsTheOriginalMenu() {
        let options = HomeShortcutCatalog.options(widgets: widgets)
        #expect(HomeShortcutCatalog.selection(stored: nil, options: options).map(\.id) == ["check-in", "add-place", "postcard"])
        #expect(HomeShortcutCatalog.nearbySlots(selectedCount: 3) == 1)
    }

    @Test func storedSelectionDropsUnknownsDuplicatesAndOverflow() {
        let options = HomeShortcutCatalog.options(widgets: widgets)
        let stored = ["widget:sleepsounds", "gone", "widget:sleepsounds", "check-in", "postcard", "add-place", "widget:water"]
        #expect(HomeShortcutCatalog.selection(stored: stored, options: options).map(\.id) == ["widget:sleepsounds", "check-in", "postcard", "add-place"])
        #expect(HomeShortcutCatalog.selection(stored: [], options: options).isEmpty)
        #expect(HomeShortcutCatalog.nearbySlots(selectedCount: 0) == 4)
    }

    @Test func togglingRespectsTheCap() {
        var selection = ["check-in", "add-place", "postcard"]
        selection = HomeShortcutCatalog.toggled("widget:water", in: selection)
        #expect(selection.count == 4)
        #expect(HomeShortcutCatalog.toggled("widget:sleepsounds", in: selection) == selection) // full
        selection = HomeShortcutCatalog.toggled("add-place", in: selection)
        #expect(selection == ["check-in", "postcard", "widget:water"])
    }

    @Test func tappedTypesRouteToPendingLinks() {
        #expect(HomeShortcutCatalog.pendingLink(forShortcutType: "com.favcircles.circles.check-in") == "check-in")
        #expect(HomeShortcutCatalog.pendingLink(forShortcutType: "com.favcircles.circles.postcard") == "widget:postcard")
        #expect(HomeShortcutCatalog.pendingLink(forShortcutType: "com.favcircles.circles.widget.heartbeat") == "widget:heartbeat")
        #expect(HomeShortcutCatalog.pendingLink(forShortcutType: "com.favcircles.circles.widget.") == nil)
        #expect(HomeShortcutCatalog.pendingLink(forShortcutType: "com.other.thing") == nil)
        // The planner still owns per-place rows and delegates the rest.
        #expect(QuickCheckInShortcutPlanner.pendingLink(forShortcutType: "com.favcircles.circles.widget.water", userInfo: nil) == "widget:water")
        #expect(QuickCheckInShortcutPlanner.pendingLink(forShortcutType: QuickCheckInShortcutPlanner.checkInAtPlaceType, userInfo: ["placeId": "p1"]) == "check-in:p1")
    }
}
