import SwiftUI
import Combine
import FirebaseAuth
import GoogleSignIn
import AuthenticationServices
import FacebookLogin
class FirebaseAuthManager: ObservableObject {
    static let shared = FirebaseAuthManager()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var firebaseUser: FirebaseAuth.User?
    @Published var isLoading = false
    @Published var error: AuthError?
    
    private var authService = AuthService.shared
    private var cancellables = Set<AnyCancellable>()
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    
    private init() {
        setupFirebaseAuthListener()
    }
    
    private func setupFirebaseAuthListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.firebaseUser = user
            
            if let user = user {
                // User is signed in with Firebase
                self?.syncWithBackend(firebaseUser: user)
            } else {
                // User is signed out
                self?.isAuthenticated = false
                self?.currentUser = nil
            }
        }
    }
    
    private func syncWithBackend(firebaseUser: FirebaseAuth.User) {
        isLoading = true
        
        // Get Firebase ID token
        firebaseUser.getIDToken { [weak self] idToken, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error getting ID token: \(error)")
                self.error = .networkError(error)
                self.isLoading = false
                return
            }
            
            guard let idToken = idToken else {
                self.error = .invalidCredentials
                self.isLoading = false
                return
            }
            
            // Create user data from Firebase user
            let userData: [String: Any] = [
                "uid": firebaseUser.uid,
                "email": firebaseUser.email ?? "",
                "displayName": firebaseUser.displayName ?? "",
                "photoURL": firebaseUser.photoURL?.absoluteString ?? ""
            ]
            
            // Sync with your backend
            self.authService.syncFirebaseUser(idToken: idToken, userData: userData) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success(let user):
                        self.isAuthenticated = true
                        self.currentUser = user
                        // Store token for offline access
                        UserDefaults.standard.set(idToken, forKey: "authToken")
                    case .failure(let error):
                        print("Backend sync error: \(error)")
                        self.error = error as? AuthError ?? .networkError(error)
                        // Still authenticated with Firebase, but backend sync failed
                        self.isAuthenticated = true
                    }
                }
            }
        }
    }
    
    // MARK: - Email/Password Authentication
    
    func login(email: String, password: String) async throws {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            // Sign in with Firebase
            let authResult = try await Auth.auth().signIn(withEmail: email, password: password)
            
            // Save email for "remember me" functionality
            if UserDefaults.standard.bool(forKey: "rememberEmail") {
                UserDefaults.standard.set(email, forKey: "savedEmail")
            }
            
            // Firebase listener will handle the rest
            await MainActor.run {
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.error = self.mapFirebaseError(error)
            }
            throw error
        }
    }
    
    func register(email: String, password: String, displayName: String) async throws {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            // Create user with Firebase
            let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
            
            // Update display name
            let changeRequest = authResult.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            
            // Send verification email
            try await authResult.user.sendEmailVerification()
            
            await MainActor.run {
                self.isLoading = false
            }
            
            // Sign out immediately after registration to require email verification
            try Auth.auth().signOut()
            
            throw AuthError.emailNotVerified
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.error = self.mapFirebaseError(error)
            }
            throw error
        }
    }
    
    // MARK: - Social Authentication
    
    func signInWithGoogle(presentingViewController: UIViewController) async throws {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            // Get Google Sign In result
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
            
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.invalidCredentials
            }
            
            // Create Firebase credential
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            
            // Sign in with Firebase
            let authResult = try await Auth.auth().signIn(with: credential)
            
            // Firebase listener will handle the rest
            await MainActor.run {
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.error = self.mapFirebaseError(error)
            }
            throw error
        }
    }
    
    func signInWithApple(authorization: ASAuthorization) async throws {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = SocialAuthService.shared.currentNonce,
                  let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                throw AuthError.invalidCredentials
            }
            
            // Create Firebase credential
            let credential = OAuthProvider.credential(
                providerID: AuthProviderID.apple,
                idToken: idTokenString,
                rawNonce: nonce
            )
            
            // Sign in with Firebase
            let authResult = try await Auth.auth().signIn(with: credential)
            
            // Update user profile if we have a name
            if let fullName = appleIDCredential.fullName {
                let displayName = PersonNameComponentsFormatter().string(from: fullName)
                let changeRequest = authResult.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }
            
            // Firebase listener will handle the rest
            await MainActor.run {
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.error = self.mapFirebaseError(error)
            }
            throw error
        }
    }
    
    func signInWithFacebook(fromViewController viewController: UIViewController) async throws {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            // Facebook login
            let loginManager = LoginManager()
            // Facebook login uses completion handler, not async/await
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                loginManager.logIn(permissions: ["public_profile", "email"], from: viewController) { result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if result?.isCancelled == true {
                        continuation.resume(throwing: AuthError.unknown("Facebook login cancelled"))
                    } else {
                        continuation.resume()
                    }
                }
            }
            
            guard let accessToken = AccessToken.current?.tokenString else {
                throw AuthError.invalidCredentials
            }
            
            // Create Firebase credential
            let credential = FacebookAuthProvider.credential(withAccessToken: accessToken)
            
            // Sign in with Firebase
            let authResult = try await Auth.auth().signIn(with: credential)
            
            // Firebase listener will handle the rest
            await MainActor.run {
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.error = self.mapFirebaseError(error)
            }
            throw error
        }
    }
    
    // LinkedIn still goes through your backend
    func signInWithLinkedIn(code: String) async throws {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                authService.loginWithSocialProvider(provider: "linkedin", token: code, name: nil, email: nil) { result in
                    switch result {
                    case .success(let user):
                        // Create custom token from your backend response
                        // This requires your backend to create Firebase custom tokens
                        if let customToken = user.firebaseCustomToken {
                            Auth.auth().signIn(withCustomToken: customToken) { authResult, error in
                                if let error = error {
                                    continuation.resume(throwing: error)
                                } else {
                                    continuation.resume()
                                }
                            }
                        } else {
                            // Fallback: Just use backend authentication
                            DispatchQueue.main.async {
                                self.currentUser = user
                                self.isAuthenticated = true
                                self.isLoading = false
                            }
                            continuation.resume()
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.error = error as? AuthError ?? .networkError(error)
            }
            throw error
        }
    }
    
    // MARK: - Logout
    
    func logout() {
        do {
            try Auth.auth().signOut()
            
            // Clear stored data
            UserDefaults.standard.removeObject(forKey: "authToken")
            
            // Clear backend session
            authService.logout { _ in }
            
            // Clear social auth sessions
            GIDSignIn.sharedInstance.signOut()
            LoginManager().logOut()
            
        } catch {
            print("Error signing out: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func mapFirebaseError(_ error: Error) -> AuthError {
        let nsError = error as NSError
        
        if let errorCode = AuthErrorCode(rawValue: nsError.code) {
            switch errorCode {
            case .invalidEmail:
                return .invalidEmail
            case .emailAlreadyInUse:
                return .emailAlreadyInUse
            case .weakPassword:
                return .weakPassword
            case .wrongPassword:
                return .invalidCredentials
            case .userNotFound:
                return .userNotFound
            case .networkError:
                return .networkError(error)
            case .unverifiedEmail:
                return .emailNotVerified
            default:
                return .unknown(error.localizedDescription)
            }
        }
        
        return .unknown(error.localizedDescription)
    }
    
    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}

// Extension for User model to include Firebase custom token
extension User {
    var firebaseCustomToken: String? {
        // This would be included in your backend response when needed
        return nil // Placeholder - your backend would provide this
    }
}