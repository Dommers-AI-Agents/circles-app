import Foundation
import AuthenticationServices
import UIKit
import CryptoKit
import SafariServices
// Import GoogleSignIn
import GoogleSignIn

// Social Authentication Service for handling Apple & Google Sign-In
class SocialAuthService: NSObject {
    static let shared = SocialAuthService()
    
    // Retain the ASAuthorizationControllerDelegate strongly
    private var currentNonce: String?
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
    
    // MARK: - Sign Out Methods
    
    func signOutFromGoogle(completion: @escaping (Bool) -> Void) {
        GIDSignIn.sharedInstance.signOut()
        print("🔍 Signed out from Google")
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
