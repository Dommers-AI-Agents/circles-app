import UIKit

/// Opens where a next step leads, from anywhere (2026-11-02: never a dead
/// end). Uses Home's own buttons and tabs, so each step opens exactly what
/// the app opens elsewhere. Call after the screen that finished is gone.
enum NextStepNavigator {

    private static var tabBar: CirclesTabBarController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController as? CirclesTabBarController }
            .first
    }

    /// Home, on the Home tab, back at its root
    private static func home(_ then: @escaping (CirclesHomeViewController) -> Void) {
        guard let tabs = tabBar,
              let nav = tabs.viewControllers?.first as? UINavigationController,
              let home = nav.viewControllers.first as? CirclesHomeViewController else { return }
        tabs.selectedIndex = 0
        nav.popToRootViewController(animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { then(home) }
    }

    /// Pushed on the current tab
    static func push(_ controller: UIViewController) {
        guard let nav = tabBar?.selectedViewController as? UINavigationController else { return }
        nav.pushViewController(controller, animated: true)
    }

    static func addPlace() { home { $0.quickAddPlaceButtonTapped() } }
    static func postMoment() { home { $0.recordReelTapped() } }
    static func moments() { home { $0.showHomeTab(.moments) } }
    static func explore() { home { _ in } }
    static func findPeople() { tabBar?.selectedIndex = 1 }
    /// Your check-ins summed up per place (2026-11-09) — not visit tracking
    static func checkIns() { push(MyCheckInsViewController()) }
    static func profile(_ user: User) { push(ProfileViewController(user: user)) }
    /// Where a step goes when it needs nothing from the screen (the
    /// server's boosts use these)
    static func opener(for step: NextStep) -> (() -> Void)? {
        switch step.id {
        case NextStep.myRewards.id: return { rewards() }
        case NextStep.findPeople.id: return { findPeople() }
        case NextStep.addPlace.id: return { addPlace() }
        case NextStep.postMoment.id: return { postMoment() }
        case NextStep.explore.id: return { explore() }
        case NextStep.myCheckIns.id: return { checkIns() }
        case NextStep.seeMoments.id: return { moments() }
        default: return nil
        }
    }

    static func rewards() {
        let hub = RewardsHubViewController()
        hub.initialTab = .rewards
        push(hub)
    }
}
