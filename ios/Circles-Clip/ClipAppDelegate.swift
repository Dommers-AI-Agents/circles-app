import UIKit

// App Clip entry point. The clip is deliberately tiny: UIKit + URLSession +
// AuthenticationServices + StoreKit only — no Firebase, no Google, no Facebook.
// Shared app code is duplicated (trimmed), never cross-linked, to keep the
// bundle far under the 15MB App Clip budget.
@main
class ClipAppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ClipSceneDelegate.self
        return configuration
    }
}
