import UIKit

/// The app-icon shortcut menu's shared pop-ups: what it is (the "i" in
/// Settings), what pinning did, and "which one should go?" when all four
/// slots are taken. The pin's pop-ups explain the menu themselves.
enum HomeShortcutPrompts {
    static func showInfo(from viewController: UIViewController) {
        AlertPresenter.showInfo(
            title: "Home Screen Shortcuts",
            message: """
            Press and hold the FavCircles icon on your iPhone's Home Screen to open a quick menu. \
            Tap an item to jump straight there without digging through the app.

            The menu holds up to \(HomeShortcutCatalog.maxSelected). Tap the pin on any widget to add it, \
            or choose them in Settings → Home Screen Shortcuts. Empty slots show "Check in at" your nearest saved places.

            Inside the app, press and hold the Home tab for the same widgets.
            """,
            from: viewController
        )
    }

    /// After a pin with room to spare: what just happened and where to find it.
    static func showPinned(title: String, from viewController: UIViewController) {
        AlertPresenter.showInfo(
            title: "Added to your shortcut menu",
            message: """
            Press and hold the FavCircles icon on your iPhone's Home Screen, then tap \(title) to jump straight here.

            Inside the app, press and hold the Home tab for the same shortcut. Tap the pin again to remove it.
            """,
            from: viewController
        )
    }

    /// All slots taken: list them and swap the chosen one for `newTitle`.
    static func askToSwap(adding newTitle: String,
                          current: [HomeShortcutOption],
                          from viewController: UIViewController,
                          sourceView: UIView? = nil,
                          onPick: @escaping (_ removedId: String) -> Void) {
        AlertPresenter.showActionSheet(
            title: "Your shortcut menu is full",
            message: """
            Pressing and holding the FavCircles icon on your iPhone's Home Screen opens a menu of up to \(HomeShortcutCatalog.maxSelected) shortcuts, and yours are all taken.

            Pick one to replace with \(newTitle), or Cancel to keep them as they are.
            """,
            actions: current.map { option in
                (title: "Replace \(option.title)", style: .default, handler: { onPick(option.id) })
            },
            from: viewController,
            sourceView: sourceView
        )
    }
}
