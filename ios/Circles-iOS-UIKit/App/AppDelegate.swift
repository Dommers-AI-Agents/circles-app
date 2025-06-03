//
//  AppDelegate.swift
//  Circles-iOS-UIKit
//
//  Created by Wesley Sgroi on 5/17/25.
//

import UIKit
import AuthenticationServices
import GoogleSignIn
import FBSDKCoreKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    // Used to store Apple Sign-In credentials for an extended period
    var appleIDCompletionHandler: ((ASAuthorization?, Error?) -> Void)?
    
    // Keep track of ASAuthorizationController to prevent it from being deallocated
    var authorizationController: ASAuthorizationController?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        // Set up Apple ID credential state observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didChangeAuthState),
            name: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil
        )
        
        // Configure Google Sign-In using configuration from Info.plist
        print("🔍 Setting up Google Sign-In configuration in AppDelegate using Info.plist")
        
        guard let infoPlist = Bundle.main.infoDictionary,
              let clientId = infoPlist["CLIENT_ID"] as? String,
              let reversedClientId = infoPlist["REVERSED_CLIENT_ID"] as? String else {
            print("🔍 ❌ Failed to load Google configuration from Info.plist in AppDelegate")
            return true
        }
        
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        print("🔍 Google Sign-In configuration complete with client ID: \(clientId)")
        
        // Verify URL scheme - IMPORTANT for Google Sign-In to work
        print("🔍 Verifying URL schemes in AppDelegate")
        var hasRequiredScheme = false
        let requiredScheme = reversedClientId
        
        if let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] {
            for urlType in urlTypes {
                if let urlSchemes = urlType["CFBundleURLSchemes"] as? [String] {
                    for scheme in urlSchemes {
                        print("🔍 Found URL scheme: \(scheme)")
                        if scheme == requiredScheme {
                            hasRequiredScheme = true
                            print("🔍 ✅ Found the Google Sign-In required URL scheme")
                        }
                    }
                }
            }
        }
        
        if !hasRequiredScheme {
            print("🔍 ⚠️ WARNING: Required Google Sign-In URL scheme not found: \(requiredScheme)")
            print("🔍 ⚠️ Google Sign-In might not work properly")
        }
        
        // Try to restore previous Google Sign-In session
        print("🔍 Attempting to restore Google Sign-In session")
        
        // Check if we have a stored auth token (our app's token, not Google's)
        if AuthService.shared.isLoggedIn {
            print("🔍 User has valid auth token, no need to restore Google session")
        } else {
            // Only attempt Google session restoration if we don't have our own auth token
            print("🔍 No auth token found, checking for Google session")
            
            // Note: GIDSignIn.sharedInstance.restorePreviousSignIn is now handled differently in newer versions
            // The SDK automatically manages session persistence
        }
        
        // Initialize Facebook SDK
        print("📘 Initializing Facebook SDK")
        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
    
    // MARK: - URL Handling for External Authentication
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Handle URL schemes for authentication services
        print("📱 URL received in AppDelegate: \(url)")

        // Check if the URL is for Apple Sign-In
        if url.absoluteString.contains("appleid") {
            print("🍎 Handling Apple Sign-In callback URL")
            // Note: Apple Sign-In is typically handled through the ASAuthorizationController delegate methods,
            // not through URL schemes. But we'll log it anyway.
            return true
        }
        
        // Log detailed information about all URLs
        print("🔍 ================== URL RECEIVED ==================")
        print("🔍 URL: \(url.absoluteString)")
        print("🔍 Host: \(url.host ?? "nil")")
        print("🔍 Path: \(url.path)")
        print("🔍 Query: \(url.query ?? "nil")")
        print("🔍 Scheme: \(url.scheme ?? "nil")")
        print("🔍 ==================================================")
        
        // Try to handle with Google Sign-In SDK
        let googleHandled = GIDSignIn.sharedInstance.handle(url)
        print("🔍 Google Sign-In SDK handling result: \(googleHandled)")
        
        if googleHandled {
            print("🔍 Google Sign-In successfully handled URL")
            return true
        }
        
        // Handle Facebook SDK
        let facebookHandled = ApplicationDelegate.shared.application(app, open: url, options: options)
        print("📘 Facebook SDK handling result: \(facebookHandled)")
        
        if facebookHandled {
            print("📘 Facebook SDK successfully handled URL")
            return true
        }
        
        // Handle LinkedIn OAuth callback
        if url.scheme == "com.favcircles.circles" && url.host == "linkedin" {
            print("🔗 LinkedIn OAuth callback received")
            let handled = SocialAuthService.shared.handleLinkedInCallback(url: url)
            return handled
        }
        
        // Handle other URL schemes your app may use
        print("📱 URL not recognized by auth providers, checking app's deep linking")
        return true
    }
    
    // MARK: - Continue Apple Sign-In
    
    @objc func didChangeAuthState(_ notification: Notification) {
        print("🍎 Apple ID credential state changed")
        // Handle sign-out when Apple ID is revoked
        AuthService.shared.logout { _ in
            // This will trigger the auth state listener in SceneDelegate
        }
    }
}

