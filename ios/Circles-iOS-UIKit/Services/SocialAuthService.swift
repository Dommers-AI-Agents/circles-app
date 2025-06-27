import Foundation
import AuthenticationServices
import UIKit
import CryptoKit
import SafariServices
// Import GoogleSignIn
import GoogleSignIn
// Import FBSDKLoginKit for Facebook
import FBSDKLoginKit
// Import for LinkedIn OAuth
import WebKit

// Social Authentication Service for handling Apple & Google Sign-In
class SocialAuthService: NSObject {
    static let shared = SocialAuthService()
    
    // Retain the ASAuthorizationControllerDelegate strongly
    var currentNonce: String?
    private var completionHandler: ((Result<User, Error>) -> Void)?
    private var presentationAnchor: ASPresentationAnchor?
    
    // Keep a strong reference to the controller to prevent deallocation during auth
    private var authorizationController: ASAuthorizationController?
    
    // Keep a strong reference to the presenting view controller during Google Sign-In
    private var presentingViewController: UIViewController?
    
    // MARK: - Apple Sign-In
    
    func signInWithApple(from viewController: UIViewController, completion: @escaping (Result<User, Error>) -> Void) {
        print("🍎 Starting Apple Sign-In process in SocialAuthService")
        self.completionHandler = completion
        
        // Store the presentation anchor (window) directly
        self.presentationAnchor = viewController.view.window
        print("🍎 Stored presentation anchor (window): \(String(describing: self.presentationAnchor))")
        
        // Generate a nonce for the authentication request
        let nonce = generateNonce(length: 32)
        self.currentNonce = nonce
        print("🍎 Generated nonce: \(nonce)")
        
        // Create Apple ID request
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        print("🍎 Created Apple ID request with scopes: \(request.requestedScopes?.description ?? "none")")
        
        // Create authorization controller and keep a strong reference
        self.authorizationController = ASAuthorizationController(authorizationRequests: [request])
        self.authorizationController?.delegate = self
        self.authorizationController?.presentationContextProvider = self
        print("🍎 Created authorization controller and set delegate and presentation context provider")
        
        // Get a reference to AppDelegate to store the controller
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.authorizationController = self.authorizationController
            print("🍎 Stored authorizationController in AppDelegate for strong reference")
        }
        
        // Perform the request
        print("🍎 About to perform authorization requests")
        self.authorizationController?.performRequests()
        print("🍎 Authorization requests performed")
    }
    
    // MARK: - Google Sign-In
    
    func signInWithGoogle(from viewController: UIViewController, completion: @escaping (Result<User, Error>) -> Void) {
        self.completionHandler = completion
        
        // CRITICAL: Store a strong reference to the view controller to prevent deallocation
        self.presentingViewController = viewController
        
        print("🔍 Starting Google Sign-In process with configuration from Info.plist")
        print("🔍 Storing strong reference to view controller: \(viewController)")
        
        // Load configuration from Info.plist
        guard let infoPlist = Bundle.main.infoDictionary,
              let clientId = infoPlist["CLIENT_ID"] as? String,
              let reversedClientId = infoPlist["REVERSED_CLIENT_ID"] as? String else {
            print("🔍 ❌ Failed to load Google configuration from Info.plist")
            let error = NSError(domain: "com.circles.auth.google", code: -1, 
                               userInfo: [NSLocalizedDescriptionKey: "Google Sign-In configuration not found in Info.plist"])
            completion(.failure(error))
            return
        }
        
        // Debug info for troubleshooting
        print("🔍 DEBUG: Loaded from Info.plist:")
        print("🔍 DEBUG: Client ID: \(clientId)")
        print("🔍 DEBUG: Reversed Client ID (URL Scheme): \(reversedClientId)")
        print("🔍 DEBUG: Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        
        // Create the Google Sign-In configuration using the plist data
        let signInConfig = GIDConfiguration(clientID: clientId)
        
        // Save the configuration
        GIDSignIn.sharedInstance.configuration = signInConfig
        
        // Verify we have the proper URL scheme registered
        if let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] {
            var hasCorrectURLScheme = false
            
            for urlType in urlTypes {
                if let urlSchemes = urlType["CFBundleURLSchemes"] as? [String] {
                    for scheme in urlSchemes {
                        print("🔍 DEBUG: Found URL scheme: \(scheme)")
                        if scheme == "com.googleusercontent.apps.778088177220-7ddtorl0um8te3s5dmv14fs4d2kirukt" {
                            hasCorrectURLScheme = true
                            print("🔍 DEBUG: ✅ Found matching Google URL scheme")
                        }
                    }
                }
            }
            
            if !hasCorrectURLScheme {
                print("🔍 DEBUG: ⚠️ Could not find the required URL scheme")
            }
        }
        
        // Start the sign-in flow
        print("🔍 DEBUG: About to start Google sign-in flow")
        
        // Add more detailed debugging for the sign-in process
        print("🔍 ==== GOOGLE SIGN-IN DEBUG INFO ====")
        print("🔍 Client ID: 778088177220-7ddtorl0um8te3s5dmv14fs4d2kirukt.apps.googleusercontent.com")
        print("🔍 View Controller: \(type(of: viewController))")
        print("🔍 Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")")
        
        // Additional parameters for OAuth flow would go here if needed
        
        // Standard sign in method
        print("🔍 Calling GIDSignIn.signIn() now...")
        
        // Add debugging to check if the call even works
        print("🔍 GIDSignIn.sharedInstance: \(GIDSignIn.sharedInstance)")
        print("🔍 GIDSignIn configuration: \(String(describing: GIDSignIn.sharedInstance.configuration))")
        
        GIDSignIn.sharedInstance.signIn(
            withPresenting: viewController
        ) { signInResult, error in
            print("🔍 ======= GOOGLE SIGN-IN CALLBACK RECEIVED =======")
            print("🔍 This message proves the callback was called")
            print("🔍 SignInResult: \(String(describing: signInResult))")
            print("🔍 Error: \(String(describing: error))")
            print("🔍 ===============================================")
            
            // Handle sign-in errors with more detailed logging
            if let error = error {
                print("🔍 ======= GOOGLE SIGN-IN ERROR =======")
                print("🔍 Error Code: \((error as NSError).code)")
                print("🔍 Error Domain: \((error as NSError).domain)")
                print("🔍 Description: \(error.localizedDescription)")
                
                // Get more details from userInfo if available
                let nsError = error as NSError
                print("🔍 User Info: \(nsError.userInfo)")
                
                print("🔍 Full Error: \(error)")
                print("🔍 ===================================")
                
                // Clean up the reference to prevent memory leaks
                self.presentingViewController = nil
                
                completion(.failure(error))
                return
            }
            
            // Ensure we have a user and authentication
            guard let user = signInResult?.user,
                  let idToken = user.idToken?.tokenString else {
                
                // Clean up the reference to prevent memory leaks
                self.presentingViewController = nil
                
                let error = NSError(
                    domain: "com.circles.auth.google",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to get valid authentication token from Google"]
                )
                completion(.failure(error))
                return
            }
            
            print("🔍 Successfully authenticated with Google, token: \(idToken)")
            print("🔍 Google User: \(user.profile?.name ?? "Unknown"), \(user.profile?.email ?? "No email")")
            
            // Clean up the reference to prevent memory leaks
            self.presentingViewController = nil
            
            // Send the token to our backend
            AuthService.shared.loginWithSocialProvider(provider: "google", token: idToken) { result in
                completion(result)
            }
        }
    }
    
    // MARK: - Session Restoration
    
    func restoreGoogleSignInSession(completion: @escaping (Result<User, Error>) -> Void) {
        print("🔍 Attempting to restore Google Sign-In session")
        
        // Check if there's a previous Google Sign-In session
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            if let error = error {
                print("🔍 Failed to restore Google session: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let user = user,
                  let idToken = user.idToken?.tokenString else {
                print("🔍 No previous Google session found")
                let error = NSError(domain: "com.circles.auth.google", code: -1, 
                                   userInfo: [NSLocalizedDescriptionKey: "No previous Google session"])
                completion(.failure(error))
                return
            }
            
            print("🔍 Successfully restored Google session for: \(user.profile?.email ?? "Unknown")")
            
            // Send the restored token to our backend
            AuthService.shared.loginWithSocialProvider(provider: "google", token: idToken) { result in
                completion(result)
            }
        }
    }
    
    // MARK: - Facebook Sign-In
    
    func signInWithFacebook(from viewController: UIViewController, completion: @escaping (Result<User, Error>) -> Void) {
        self.completionHandler = completion
        
        print("📘 Starting Facebook Sign-In process")
        
        let loginManager = LoginManager()
        loginManager.logOut() // Clear any existing session
        
        // Note: "email" permission requires app to be in live mode or user to be a test user
        // For development, you can use just "public_profile" or add test users in Facebook App Dashboard
        loginManager.logIn(permissions: ["public_profile", "email"], from: viewController) { [weak self] result, error in
            if let error = error {
                print("📘 Facebook Sign-In error: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let result = result, !result.isCancelled else {
                print("📘 Facebook Sign-In cancelled")
                let error = NSError(domain: "com.circles.auth.facebook", code: -1, 
                                   userInfo: [NSLocalizedDescriptionKey: "Facebook sign-in was cancelled"])
                completion(.failure(error))
                return
            }
            
            // Get the access token
            guard let token = AccessToken.current?.tokenString else {
                print("📘 Failed to get Facebook access token")
                let error = NSError(domain: "com.circles.auth.facebook", code: -1, 
                                   userInfo: [NSLocalizedDescriptionKey: "Failed to get Facebook access token"])
                completion(.failure(error))
                return
            }
            
            print("📘 Successfully authenticated with Facebook, token: \(token)")
            
            // Fetch user profile data
            let request = GraphRequest(graphPath: "me", parameters: ["fields": "id,name,email,picture.type(large)"])
            request.start { _, graphResult, error in
                if let error = error {
                    print("📘 Failed to fetch Facebook profile: \(error)")
                    completion(.failure(error))
                    return
                }
                
                guard let userData = graphResult as? [String: Any] else {
                    let error = NSError(domain: "com.circles.auth.facebook", code: -1, 
                                       userInfo: [NSLocalizedDescriptionKey: "Failed to parse Facebook user data"])
                    completion(.failure(error))
                    return
                }
                
                let name = userData["name"] as? String
                let email = userData["email"] as? String
                var picture: String?
                
                if let pictureData = userData["picture"] as? [String: Any],
                   let data = pictureData["data"] as? [String: Any],
                   let url = data["url"] as? String {
                    picture = url
                }
                
                print("📘 Facebook User: \(name ?? "Unknown"), \(email ?? "No email")")
                
                // Send the token to our backend
                AuthService.shared.loginWithSocialProvider(provider: "facebook", token: token, name: name, email: email) { result in
                    completion(result)
                }
            }
        }
    }
    
    // MARK: - LinkedIn Sign-In
    
    func signInWithLinkedIn(from viewController: UIViewController, completion: @escaping (Result<User, Error>) -> Void) {
        self.completionHandler = completion
        self.presentingViewController = viewController
        
        print("🔗 Starting LinkedIn Sign-In process")
        
        // LinkedIn OAuth 2.0 configuration
        guard let clientId = Bundle.main.object(forInfoDictionaryKey: "LinkedInClientID") as? String,
              clientId != "YOUR_LINKEDIN_CLIENT_ID" else {
            print("🔗 LinkedIn Client ID not configured in Info.plist")
            let error = NSError(domain: "com.circles.auth.linkedin", code: -10,
                               userInfo: [NSLocalizedDescriptionKey: "LinkedIn Client ID not configured"])
            completion(.failure(error))
            return
        }
        
        // Use the backend URL for LinkedIn OAuth callback
        // LinkedIn will redirect to backend, which then redirects to app
        let redirectUri = "https://circles-backend-196924649787.us-central1.run.app/auth/linkedin/callback"
        let state = UUID().uuidString
        let scope = "openid profile email"
        
        // Store state for verification
        UserDefaults.standard.set(state, forKey: "linkedInAuthState")
        
        // Build authorization URL
        var components = URLComponents(string: "https://www.linkedin.com/oauth/v2/authorization")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scope)
        ]
        
        guard let authURL = components.url else {
            let error = NSError(domain: "com.circles.auth.linkedin", code: -1, 
                               userInfo: [NSLocalizedDescriptionKey: "Failed to create LinkedIn authorization URL"])
            completion(.failure(error))
            return
        }
        
        // Present Safari view controller for OAuth flow
        print("🔗 Opening LinkedIn authorization URL: \(authURL.absoluteString)")
        let safariViewController = SFSafariViewController(url: authURL)
        safariViewController.delegate = self
        safariViewController.preferredBarTintColor = Constants.Colors.primary
        safariViewController.preferredControlTintColor = .white
        viewController.present(safariViewController, animated: true) {
            print("🔗 Safari view controller presented successfully")
        }
    }
    
    // MARK: - Sign Out Methods
    
    func signOutFromGoogle(completion: @escaping (Bool) -> Void) {
        GIDSignIn.sharedInstance.signOut()
        print("🔍 Signed out from Google")
        completion(true)
    }
    
    func signOutFromFacebook(completion: @escaping (Bool) -> Void) {
        LoginManager().logOut()
        print("📘 Signed out from Facebook")
        completion(true)
    }
    
    // MARK: - Helper Methods
    
    // Generate random nonce for Apple Sign-In
    private func generateNonce(length: Int) -> String {
        let charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            for random in randoms {
                if remainingLength == 0 {
                    break
                }
                
                if random < charset.count {
                    let index = charset.index(charset.startIndex, offsetBy: Int(random))
                    result.append(charset[index])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    // Hash the nonce with SHA-256 for Apple Sign-In security
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension SocialAuthService: ASAuthorizationControllerDelegate {
    // Handle authorization success
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        print("🍎 Authorization completed successfully")
        
        // Extract credentials
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
           let identityToken = appleIDCredential.identityToken,
           let tokenString = String(data: identityToken, encoding: .utf8) {
            
            print("🍎 Successfully got Apple ID credential")
            
            // Get user info (not directly used here, but would be in a full implementation)
            let userId = appleIDCredential.user
            let fullName = appleIDCredential.fullName
            let email = appleIDCredential.email
            
            print("🍎 User ID: \(userId)")
            print("🍎 Full Name: \(fullName?.givenName ?? "nil") \(fullName?.familyName ?? "nil")")
            print("🍎 Email: \(email ?? "nil")")
            
            // Create a display name from the full name components
            var displayName: String? = nil
            if let givenName = fullName?.givenName, let familyName = fullName?.familyName {
                displayName = "\(givenName) \(familyName)"
            } else if let givenName = fullName?.givenName {
                displayName = givenName
            } else if let familyName = fullName?.familyName {
                displayName = familyName
            }
            
            if let name = displayName {
                print("🍎 Signing in with Apple as: \(name)")
            } else {
                print("🍎 No name provided by Apple Sign-In")
            }
            
            // Clean up strong references 
            authorizationController = nil
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                appDelegate.authorizationController = nil
            }
            
            // Send the token to our backend via the AuthService with name and email
            print("🍎 Calling AuthService.loginWithSocialProvider with token, name: \(displayName ?? "nil"), email: \(email ?? "nil")")
            AuthService.shared.loginWithSocialProvider(provider: "apple", token: tokenString, name: displayName, email: email) { [weak self] result in
                print("🍎 AuthService.loginWithSocialProvider completed")
                self?.completionHandler?(result)
            }
        } else {
            print("🍎 Failed to get Apple ID credential from authorization")
            
            // Clean up strong references
            authorizationController = nil
            if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                appDelegate.authorizationController = nil
            }
            
            let error = NSError(domain: "com.circles.auth.apple", code: 100, userInfo: [NSLocalizedDescriptionKey: "Could not get Apple ID credentials from authorization response"])
            completionHandler?(.failure(error))
        }
    }
    
    // Handle authorization failure
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("🍎 Authorization failed with error: \(error.localizedDescription)")
        print("🍎 Error details: \(error)")
        
        // Get more detailed error information
        var errorMessage = error.localizedDescription
        
        // Check for specific ASAuthorizationError codes
        let authError = error as? ASAuthorizationError
        if let code = authError?.code {
            switch code {
            case .canceled:
                errorMessage = "The authorization was canceled by the user"
            case .failed:
                errorMessage = "The authorization request failed"
            case .invalidResponse:
                errorMessage = "The authorization request received an invalid response"
            case .notHandled:
                errorMessage = "The authorization request wasn't handled"
            case .unknown:
                errorMessage = "The authorization request failed for an unknown reason"
            default:
                errorMessage = "Authorization failed with code: \(code.rawValue)"
            }
        }
        
        print("🍎 Detailed error: \(errorMessage)")
        
        // Clean up strong references
        authorizationController = nil
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.authorizationController = nil
        }
        
        // Call completion handler with detailed error
        let detailedError = NSError(domain: "com.circles.auth.apple", 
                                   code: (authError?.code.rawValue ?? -1), 
                                   userInfo: [NSLocalizedDescriptionKey: errorMessage])
        completionHandler?(.failure(detailedError))
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension SocialAuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        print("🍎 presentationAnchor called for controller")
        
        if let anchor = self.presentationAnchor {
            print("🍎 Using stored presentation anchor")
            return anchor
        }
        
        print("🍎 Using fallback to UIApplication.shared.windows.first")
        
        // Use the scene API for iOS 13+
        if #available(iOS 13.0, *) {
            // Get the first available scene with connected window
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    for window in windowScene.windows {
                        if window.isKeyWindow {
                            print("🍎 Found key window using UIWindowScene: \(window)")
                            return window
                        }
                    }
                    
                    // If no key window found, use the first window
                    if let window = windowScene.windows.first {
                        print("🍎 Found first window using UIWindowScene: \(window)")
                        return window
                    }
                }
            }
        }
        
        // Legacy fallback for iOS 12 and below (although Sign in with Apple needs iOS 13+)
        // This is deprecated but we need it as a last resort fallback
        if let window = UIApplication.shared.delegate?.window ?? nil {
            print("🍎 Found window using UIApplication.shared.delegate?.window: \(window)")
            return window
        }
        
        // Last resort fallback using deprecated API
        #if swift(>=5.1)
        if #available(iOS 15.0, *) {
            // Use the new scene-based API for iOS 15+
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    if let window = windowScene.windows.first {
                        print("🍎 Found window using scene-based API: \(window)")
                        return window
                    }
                }
            }
        } else if #available(iOS 13.0, *) {
            // This is deprecated in iOS 15 but still works in iOS 13-14
            if let window = UIApplication.shared.windows.first {
                print("🍎 Found window using older windows array: \(window)")
                return window
            }
        }
        #endif
        
        // If everything else fails
        fatalError("🍎 Failed to find a valid window for Apple Sign-In")
    }
}

// MARK: - SFSafariViewControllerDelegate

extension SocialAuthService: SFSafariViewControllerDelegate {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        print("🔗 LinkedIn Safari view controller dismissed by user")
        // Only treat as cancellation if we haven't received a callback
        if completionHandler != nil {
            let error = NSError(domain: "com.circles.auth.linkedin", code: -1, 
                               userInfo: [NSLocalizedDescriptionKey: "LinkedIn sign-in was cancelled"])
            completionHandler?(.failure(error))
            completionHandler = nil
        }
        presentingViewController = nil
    }
}

// MARK: - LinkedIn OAuth Callback Handler

extension SocialAuthService {
    func handleLinkedInCallback(url: URL) -> Bool {
        print("🔗 handleLinkedInCallback called with URL: \(url.absoluteString)")
        
        guard url.scheme == "com.favcircles.circles" else {
            print("🔗 URL scheme doesn't match, expected: com.favcircles.circles, got: \(url.scheme ?? "nil")")
            return false
        }
        
        // LinkedIn callback can be in format: com.favcircles.circles://linkedin/callback
        // So we need to check if the URL contains linkedin callback
        let urlString = url.absoluteString
        guard urlString.contains("linkedin") && urlString.contains("callback") else {
            print("🔗 URL doesn't contain linkedin callback pattern")
            return false
        }
        
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
        let state = components?.queryItems?.first(where: { $0.name == "state" })?.value
        let error = components?.queryItems?.first(where: { $0.name == "error" })?.value
        
        // Verify state
        let savedState = UserDefaults.standard.string(forKey: "linkedInAuthState")
        UserDefaults.standard.removeObject(forKey: "linkedInAuthState")
        
        if state != savedState {
            print("🔗 LinkedIn state mismatch")
            let error = NSError(domain: "com.circles.auth.linkedin", code: -1, 
                               userInfo: [NSLocalizedDescriptionKey: "LinkedIn authentication state mismatch"])
            completionHandler?(.failure(error))
            // Dismiss Safari view controller
            presentingViewController?.dismiss(animated: true)
            presentingViewController = nil
            return true
        }
        
        if let error = error {
            print("🔗 LinkedIn OAuth error: \(error)")
            let authError = NSError(domain: "com.circles.auth.linkedin", code: -1, 
                                   userInfo: [NSLocalizedDescriptionKey: "LinkedIn authentication failed: \(error)"])
            completionHandler?(.failure(authError))
            // Dismiss Safari view controller
            presentingViewController?.dismiss(animated: true)
            presentingViewController = nil
            return true
        }
        
        guard let authCode = code else {
            print("🔗 No authorization code received from LinkedIn")
            let error = NSError(domain: "com.circles.auth.linkedin", code: -1, 
                               userInfo: [NSLocalizedDescriptionKey: "No authorization code received from LinkedIn"])
            completionHandler?(.failure(error))
            // Dismiss Safari view controller
            presentingViewController?.dismiss(animated: true)
            presentingViewController = nil
            return true
        }
        
        // Dismiss Safari view controller if it's still presented
        if let viewController = self.presentingViewController {
            viewController.dismiss(animated: true) {
                print("🔗 Safari view controller dismissed after successful callback")
            }
        }
        
        // Send authorization code to backend for secure token exchange
        print("🔗 Sending authorization code to backend for token exchange")
        
        // The backend will handle the client secret securely
        AuthService.shared.loginWithSocialProvider(
            provider: "linkedin",
            token: authCode, // Send authorization code, not access token
            name: nil,
            email: nil
        ) { [weak self] result in
            self?.completionHandler?(result)
            self?.presentingViewController = nil
        }
        
        return true
    }
    
    private func fetchLinkedInProfile(accessToken: String) {
        var request = URLRequest(url: URL(string: "https://api.linkedin.com/v2/me")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("🔗 LinkedIn profile fetch error: \(error)")
                self?.completionHandler?(.failure(error))
                return
            }
            
            guard let data = data,
                  let profile = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let error = NSError(domain: "com.circles.auth.linkedin", code: -1, 
                                   userInfo: [NSLocalizedDescriptionKey: "Failed to parse LinkedIn profile"])
                self?.completionHandler?(.failure(error))
                return
            }
            
            // Extract user info from LinkedIn profile
            let firstName = profile["localizedFirstName"] as? String ?? ""
            let lastName = profile["localizedLastName"] as? String ?? ""
            let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            
            print("🔗 LinkedIn User: \(name)")
            
            // Fetch email separately (requires different endpoint)
            self?.fetchLinkedInEmail(accessToken: accessToken, name: name)
        }.resume()
    }
    
    private func fetchLinkedInEmail(accessToken: String, name: String) {
        var request = URLRequest(url: URL(string: "https://api.linkedin.com/v2/emailAddress?q=members&projection=(elements*(handle~))")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            var email: String?
            
            if let data = data,
               let emailResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let elements = emailResponse["elements"] as? [[String: Any]],
               let firstElement = elements.first,
               let handle = firstElement["handle~"] as? [String: Any],
               let emailAddress = handle["emailAddress"] as? String {
                email = emailAddress
            }
            
            print("🔗 LinkedIn Email: \(email ?? "No email")")
            
            // Send the token to our backend
            DispatchQueue.main.async {
                // Dismiss Safari view controller if it's still presented
                if let viewController = self?.presentingViewController {
                    viewController.dismiss(animated: true) {
                        self?.presentingViewController = nil
                    }
                }
                
                AuthService.shared.loginWithSocialProvider(provider: "linkedin", token: accessToken, name: name.isEmpty ? nil : name, email: email) { result in
                    self?.completionHandler?(result)
                }
            }
        }.resume()
    }
}
