import UIKit

/// The app-icon shortcut menu's shared pop-ups: what it is (the "i" on a
/// widget page and in Settings) and "which one should go?" when all four
/// slots are taken.
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

    /// All slots taken: list them and swap the chosen one for `newTitle`.
    static func askToSwap(adding newTitle: String,
                          current: [HomeShortcutOption],
                          from viewController: UIViewController,
                          sourceView: UIView? = nil,
                          onPick: @escaping (_ removedId: String) -> Void) {
        AlertPresenter.showActionSheet(
            title: "Your shortcut menu is full",
            message: "It holds \(HomeShortcutCatalog.maxSelected). Pick one to replace with \(newTitle).",
            actions: current.map { option in
                (title: "Replace \(option.title)", style: .default, handler: { onPick(option.id) })
            },
            from: viewController,
            sourceView: sourceView
        )
    }
}
