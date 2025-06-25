import SwiftUI
import Firebase
import GoogleSignIn
import AuthenticationServices

struct CirclesApp: App {
    @UIApplicationDelegateAdaptor(SwiftUIAppDelegate.self) var appDelegate
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var circleManager = CircleManager.shared
    @StateObject private var userManager = UserManager.shared
    @StateObject private var placeManager = PlaceManager.shared
    @StateObject private var networkManager = NetworkManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(circleManager)
                .environmentObject(userManager)
                .environmentObject(placeManager)
                .environmentObject(networkManager)
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }
    
    private func handleURL(_ url: URL) {
        // Handle deep links
        if url.scheme == "circles" {
            // Handle circles:// URLs
            if url.host == "circle", let circleId = url.pathComponents.last {
                // Navigate to circle detail
                circleManager.navigateToCircle(id: circleId)
            }
        } else if url.scheme == "circlesapp" {
            // Handle OAuth callbacks
            if url.host == "linkedin" {
                SocialAuthService.shared.handleLinkedInCallback(url: url)
            }
        } else {
            // Handle Google Sign In
            GIDSignIn.sharedInstance.handle(url)
        }
    }
}

// SwiftUI-compatible AppDelegate
class SwiftUIAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
        // Configure Google Sign In
        guard let clientID = FirebaseApp.app()?.options.clientID else { return false }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        
        // Configure appearance
        configureAppearance()
        
        return true
    }
    
    private func configureAppearance() {
        // Configure navigation bar appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 1.0)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = .white
        
        // Configure tab bar
        UITabBar.appearance().tintColor = UIColor(red: 0.0, green: 122.0/255.0, blue: 1.0, alpha: 1.0)
    }
}