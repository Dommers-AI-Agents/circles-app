import UIKit

/// The on-screen buttons of a tab bar, left to right, so a tour bubble can
/// point at one tab (My Network, Messages, Me) rather than the whole bar.
///
/// UIKit doesn't expose them. Before iOS 26 they were `UITabBarButton`s
/// directly under the bar; the floating Liquid Glass bar nests `_UITabButton`s
/// two levels down, and draws each one twice (a normal and a selected copy).
/// So: search the whole bar for either name and keep one per position
/// (Wes, 2026-11-12: the My Network and Me bubbles pointed at nothing).
enum TabBarButtonFinder {

    static func buttons(in tabBar: UITabBar) -> [UIView] {
        var found: [UIView] = []
        func walk(_ view: UIView) {
            let name = String(describing: type(of: view))
            if name.contains("TabBarButton") || name.contains("TabButton") {
                found.append(view)
                return
            }
            view.subviews.forEach(walk)
        }
        tabBar.subviews.forEach(walk)

        // One per position (the selected copy sits exactly over the normal one)
        var byX: [Int: UIView] = [:]
        for view in found where !view.isHidden && view.alpha > 0.01 {
            let x = Int(view.convert(view.bounds, to: tabBar).midX.rounded())
            if byX[x] == nil { byX[x] = view }
        }
        return byX.keys.sorted().compactMap { byX[$0] }
    }

    static func button(in tabBar: UITabBar, at index: Int) -> UIView? {
        let all = buttons(in: tabBar)
        return all.indices.contains(index) ? all[index] : nil
    }
}
