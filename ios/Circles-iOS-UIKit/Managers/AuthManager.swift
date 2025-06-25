import SwiftUI
import Combine
import FirebaseAuth

class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var firebaseUser: FirebaseAuth.User?
    @Published var isLoading = false
    @Published var error: AuthError?
    
    private var cancellables = Set<AnyCancellable>()
    private let authService = AuthService.shared
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var isFirebaseConfigured = false
    
    private init() {
        setupAuthStateListener()
        // Firebase auth listener will be set up after Firebase is configured
    }
    
    func configureFirebaseAuth() {
        guard !isFirebaseConfigured else { return }
        isFirebaseConfigured = true
        setupFirebaseAuthListener()
    }
    
    private func setupAuthStateListener() {
        // Listen to auth state changes
        authService.addAuthStateListener(id: "AuthManager") { [weak self] isLoggedIn in
            DispatchQueue.main.async {
                self?.isAuthenticated = isLoggedIn
                if isLoggedIn {
                    self?.fetchCurrentUser()
                } else {
                    self?.currentUser = nil
                }
            }
        }
    }
    
    private func setupFirebaseAuthListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.firebaseUser = user
            
            if let user = user {
                // User is signed in with Firebase
                self?.syncWithBackend(firebaseUser: user)
            } else {
                // User is signed out
                DispatchQueue.main.async {
                    self?.isAuthenticated = false
                    self?.currentUser = nil
                }
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
                self.isLoading = false
                return
            }
            
            guard let idToken = idToken else {
                self.isLoading = false
                return
            }
            
            // Store the Firebase ID token
            UserDefaults.standard.set(idToken, forKey: "firebaseIdToken")
            
            // Continue using existing auth flow
            self.fetchCurrentUser()
        }
    }
    
    func checkAuthenticationStatus() {
        isAuthenticated = authService.isLoggedIn
        if isAuthenticated {
            fetchCurrentUser()
        }
    }
    
    func login(email: String, password: String) async throws {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            try await withCheckedThrowingContinuation { continuation in
                authService.login(email: email, password: password) { result in
                    switch result {
                    case .success(let user):
                        DispatchQueue.main.async {
                            self.currentUser = user
                            self.isAuthenticated = true
                            self.isLoading = false
                        }
                        continuation.resume()
                    case .failure(let error):
                        DispatchQueue.main.async {
                            self.error = error as? AuthError
                            self.isLoading = false
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.error = error as? AuthError
                self.isLoading = false
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
            try await withCheckedThrowingContinuation { continuation in
                authService.register(email: email, password: password, displayName: displayName) { result in
                    switch result {
                    case .success(_):
                        DispatchQueue.main.async {
                            self.isLoading = false
                        }
                        continuation.resume()
                    case .failure(let error):
                        DispatchQueue.main.async {
                            self.error = error as? AuthError
                            self.isLoading = false
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.error = error as? AuthError
                self.isLoading = false
            }
            throw error
        }
    }
    
    func loginWithSocial(provider: String, token: String, name: String? = nil, email: String? = nil) async throws {
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        do {
            try await withCheckedThrowingContinuation { continuation in
                authService.loginWithSocialProvider(provider: provider, token: token, name: name, email: email) { result in
                    switch result {
                    case .success(let user):
                        DispatchQueue.main.async {
                            self.currentUser = user
                            self.isAuthenticated = true
                            self.isLoading = false
                        }
                        continuation.resume()
                    case .failure(let error):
                        DispatchQueue.main.async {
                            self.error = error as? AuthError
                            self.isLoading = false
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.error = error as? AuthError
                self.isLoading = false
            }
            throw error
        }
    }
    
    func logout() {
        authService.logout { _ in
            DispatchQueue.main.async {
                self.currentUser = nil
                self.isAuthenticated = false
            }
        }
    }
    
    private func fetchCurrentUser() {
        authService.fetchCurrentUser { result in
            switch result {
            case .success(let user):
                DispatchQueue.main.async {
                    self.currentUser = user
                }
            case .failure(let error):
                print("Failed to fetch current user: \(error)")
            }
        }
    }
    
    func updateCurrentUser(_ user: User) {
        DispatchQueue.main.async {
            self.currentUser = user
        }
    }
    
    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}