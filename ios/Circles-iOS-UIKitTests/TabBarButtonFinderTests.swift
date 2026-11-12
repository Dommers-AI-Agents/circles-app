import Testing
import UIKit
@testable import Circles_iOS

/// A tour bubble can find each tab's button on the bar the app really runs on
/// (the floating bar nests them and draws each twice).
@MainActor
struct TabBarButtonFinderTests {
    @Test func findsOneButtonPerTabLeftToRight() async throws {
        let tabs = UITabBarController()
        tabs.viewControllers = ["Home", "My Network", "Messages", "Me"].map { title in
            let vc = UIViewController()
            vc.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: "person"), tag: 0)
            return vc
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        tabs.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)

        let buttons = TabBarButtonFinder.buttons(in: tabs.tabBar)
        #expect(buttons.count == 4)
        let xs = buttons.map { $0.convert($0.bounds, to: window).midX }
        #expect(xs == xs.sorted())
        #expect(TabBarButtonFinder.button(in: tabs.tabBar, at: 3) === buttons.last)
        #expect(TabBarButtonFinder.button(in: tabs.tabBar, at: 4) == nil)
    }
}
