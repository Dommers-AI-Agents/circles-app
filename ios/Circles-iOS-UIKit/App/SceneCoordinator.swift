import UIKit

/// A helper SceneDelegate owns (deep links, invites, first session, re-auth…).
/// It reaches the scene's window through its host, so code moved out of
/// SceneDelegate reads the same as it did there.
@MainActor
protocol SceneCoordinator: AnyObject {
    var host: SceneDelegate? { get }
}

extension SceneCoordinator {
    var window: UIWindow? { host?.window }

    /// The top-most presented view controller, for presenting alerts
    func topViewController() -> UIViewController? {
        guard var topController = window?.rootViewController else { return nil }
        while let presented = topController.presentedViewController {
            topController = presented
        }
        return topController
    }
}
