import Foundation

// Authentication-related errors
enum AuthError: Error, LocalizedError, Equatable {
    case invalidCredentials
    case accountExists
    case accountNotFound
    case tokenExpired
    case networkError(Error)
    case emailNotVerified
    case invalidEmail
    case emailAlreadyInUse
    case weakPassword
    case userNotFound
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .accountExists:
            return "An account with this email already exists"
        case .accountNotFound:
            return "Account not found"
        case .tokenExpired:
            return "Your session has expired. Please log in again"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .emailNotVerified:
            return "Please verify your email before logging in. Check your inbox for the verification link."
        case .invalidEmail:
            return "Please enter a valid email address"
        case .emailAlreadyInUse:
            return "An account with this email already exists"
        case .weakPassword:
            return "Password must be at least 6 characters"
        case .userNotFound:
            return "No account found with this email"
        case .unknown(let message):
            return message
        }
    }
    
    static func == (lhs: AuthError, rhs: AuthError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidCredentials, .invalidCredentials),
             (.accountExists, .accountExists),
             (.accountNotFound, .accountNotFound),
             (.tokenExpired, .tokenExpired),
             (.emailNotVerified, .emailNotVerified),
             (.invalidEmail, .invalidEmail),
             (.emailAlreadyInUse, .emailAlreadyInUse),
             (.weakPassword, .weakPassword),
             (.userNotFound, .userNotFound):
            return true
        case (.networkError(let lhsError), .networkError(let rhsError)):
            return (lhsError as NSError) == (rhsError as NSError)
        case (.unknown(let lhsMsg), .unknown(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

// Authentication service
class AuthService {
    static let shared = AuthService()
    
    private let keychainService = KeychainService.shared
    private let userDefaults = UserDefaults.standard
    private let tokenKey = "authToken"
    private let refreshTokenKey = "refreshToken"
    private let userIdKey = "userId"
    private let authProviderKey = "authProvider"
    
    // Authentication state
    private var _currentUser: User?
    
    // Public getter for current user
    var currentUser: User? {
        return _currentUser
    }
    
    // Update current user
    func updateCurrentUser(_ user: User) {
        _currentUser = user
        // Note: AuthManager removed - listeners notified via authStateListeners
    }
    
    // Auth state change listeners
    private var authStateListeners: [String: (Bool) -> Void] = [:]
    
    var isLoggedIn: Bool {
        let token = getToken()
        let loggedIn = token != nil
        print("🔐 AuthService: isLoggedIn called, token exists: \(token != nil), returning: \(loggedIn)")
        return loggedIn
    }
    
    func isTokenExpired() -> Bool {
        return keychainService.isTokenExpired()
    }
    
    func shouldRefreshToken() -> Bool {
        guard let expiration = keychainService.getTokenExpiration() else {
            // If no expiration date, don't refresh
            return false
        }
        
        // Refresh if token expires in less than 5 minutes
        let timeUntilExpiration = expiration.timeIntervalSinceNow
        return timeUntilExpiration < 300 // 5 minutes
    }
    
    private init() {
        // Migrate existing tokens from UserDefaults to Keychain
        keychainService.migrateFromUserDefaults()
        
        // Load token from Keychain if available
        if let token = keychainService.getAuthToken() {
            APIService.shared.setAuthToken(token)
        }
        
        if let refreshToken = keychainService.getRefreshToken() {
            APIService.shared.setRefreshToken(refreshToken)
        }
    }
    
    // MARK: - Authentication Methods
    
    func register(email: String, password: String, displayName: String, completion: @escaping (Result<User, Error>) -> Void) {
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "displayName": displayName
        ]
        
        APIService.shared.request(
            endpoint: "auth/register",
            method: .post,
            body: body,
            requiresAuth: false
        ) { [weak self] (result: Result<AuthResponse, APIError>) in
            switch result {
            case .success(let response):
                self?.handleAuthResponse(response, completion: completion)
            case .failure(let error):
                let authError = self?.mapAPIErrorToAuthError(error, context: .register)
                completion(.failure(authError ?? error))
            }
        }
    }
    
    func login(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
        let body: [String: Any] = [
            "email": email,
            "password": password
        ]
        
        APIService.shared.request(
            endpoint: "auth/login",
            method: .post,
            body: body,
            requiresAuth: false
        ) { [weak self] (result: Result<AuthResponse, APIError>) in
            switch result {
            case .success(let response):
                // Save auth provider as "email" for email/password login
                self?.saveAuthProvider("email")
                self?.handleAuthResponse(response, completion: completion)
            case .failure(let error):
                let authError = self?.mapAPIErrorToAuthError(error, context: .login)
                completion(.failure(authError ?? error))
            }
        }
    }
    
    func loginWithSocialProvider(provider: String, token: String, name: String? = nil, email: String? = nil, completion: @escaping (Result<User, Error>) -> Void) {
        print("🔐 AuthService.loginWithSocialProvider called with provider: \(provider)")
        
        // Use different endpoints for different providers
        let endpoint: String
        var body: [String: Any] = [:]
        
        switch provider {
        case "linkedin":
            // LinkedIn uses authorization code exchange
            endpoint = "auth/linkedin"
            body["code"] = token // LinkedIn sends authorization code, not token
            if let name = name {
                body["name"] = name
            }
            if let email = email {
                body["email"] = email
            }
        default:
            // Other providers (Apple, Google, Facebook) use Firebase
            endpoint = "auth/firebase"
            body["idToken"] = token
            if let name = name {
                body["name"] = name
            }
            if let email = email {
                body["email"] = email
            }
        }
        
        APIService.shared.request(
            endpoint: endpoint,
            method: .post,
            body: body,
            requiresAuth: false
        ) { [weak self] (result: Result<AuthResponse, APIError>) in
            print("🔐 AuthService.loginWithSocialProvider API response received")
            
            switch result {
            case .success(let response):
                print("🔐 Social login successful, handling auth response")
                // Save the auth provider for session restoration
                self?.saveAuthProvider(provider)
                self?.handleAuthResponse(response, completion: completion)
            case .failure(let error):
                print("🔐 Social login failed with error: \(error)")
                let authError = self?.mapAPIErrorToAuthError(error, context: .login)
                completion(.failure(authError ?? error))
            }
        }
    }
    
    func refreshToken(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let refreshToken = keychainService.getRefreshToken() else {
            completion(.failure(AuthError.tokenExpired))
            return
        }
        
        let body: [String: Any] = [
            "refreshToken": refreshToken
        ]
        
        APIService.shared.request(
            endpoint: "auth/refresh-token",
            method: .post,
            body: body,
            requiresAuth: false
        ) { [weak self] (result: Result<RefreshTokenResponse, APIError>) in
            switch result {
            case .success(let response):
                if let token = response.token {
                    self?.saveToken(token)
                    APIService.shared.setAuthToken(token)
                    completion(.success(()))
                } else {
                    completion(.failure(AuthError.tokenExpired))
                }
            case .failure(let error):
                let authError = self?.mapAPIErrorToAuthError(error, context: .refreshToken)
                completion(.failure(authError ?? error))
            }
        }
    }
    
    func logout(completion: ((Bool) -> Void)? = nil) {
        // Handle notifications cleanup
        NotificationService.shared.handleUserLogout()
        
        // Clear all cached data from various services
        PreloadManager.shared.clearPreloadedData()
        CategoryService.shared.clearCache()
        
        // Clear MessagingManager cached data
        MessagingManager.shared.clearCache()
        
        // Clear NetworkManager cached data
        NetworkManager.shared.clearCache()
        
        // Clear ImageService cache
        ImageService.shared.clearCache()
        
        // Clear StreetViewService cache
        StreetViewService.shared.clearCache()
        
        // Clear app-specific UserDefaults
        clearAppUserDefaults()
        
        // Attempt to notify server about logout
        APIService.shared.request(
            endpoint: "auth/logout",
            method: .post,
            requiresAuth: true
        ) { [weak self] (result: Result<EmptyResponse, APIError>) in
            // Regardless of server response, clear local tokens
            self?.clearLocalAuth()
            
            // Sign out from Google
            SocialAuthService.shared.signOutFromGoogle { _ in
                // Notify auth state change
                self?.notifyAuthStateChange(isLoggedIn: false)
                
                completion?(true)
            }
        }
    }
    
    func fetchCurrentUser(completion: @escaping (Result<User, Error>) -> Void) {
        // If we already have the current user cached and it's from the current session, return it
        if let currentUser = _currentUser, getUserId() == currentUser.id {
            print("🔐 Returning cached current user: \(currentUser.displayName)")
            completion(.success(currentUser))
            return
        }
        
        // Otherwise fetch from the API
        guard let userId = getUserId() else {
            print("🔐 No user ID found, cannot fetch current user")
            completion(.failure(AuthError.tokenExpired))
            return
        }
        
        print("🔐 Fetching current user with ID: \(userId)")
        
        // Use the specific user endpoint instead of /me endpoint which seems to have issues
        APIService.shared.request(
            endpoint: "users/\(userId)",
            method: .get,
            requiresAuth: true
        ) { [weak self] (result: Result<UserResponse, APIError>) in
            switch result {
            case .success(let response):
                print("🔐 Successfully fetched current user: \(response.user.displayName)")
                self?._currentUser = response.user
                completion(.success(response.user))
            case .failure(let error):
                print("🔐 Failed to fetch current user: \(error)")
                
                // If user not found (404), clear the invalid session
                if case .httpError(404, _) = error {
                    print("🔐 User not found (404) - clearing invalid session")
                    self?.clearLocalAuth()
                    self?.notifyAuthStateChange(isLoggedIn: false)
                    completion(.failure(AuthError.userNotFound))
                } else {
                    let authError = self?.mapAPIErrorToAuthError(error, context: .fetchUser)
                    completion(.failure(authError ?? error))
                }
            }
        }
    }
    
    // MARK: - Email Verification Methods
    
    func sendVerificationEmail(completion: @escaping (Result<Void, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "auth/send-verification-email",
            method: .post,
            requiresAuth: true
        ) { (result: Result<EmptyResponse, APIError>) in
            switch result {
            case .success(_):
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func checkEmailVerificationStatus(completion: @escaping (Result<Bool, Error>) -> Void) {
        APIService.shared.request(
            endpoint: "auth/verification-status",
            method: .get,
            requiresAuth: true
        ) { (result: Result<VerificationStatusResponse, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.isVerified))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Firebase Integration
    
    func syncFirebaseUser(idToken: String, userData: [String: Any], completion: @escaping (Result<User, Error>) -> Void) {
        var body = userData
        body["firebaseIdToken"] = idToken
        
        APIService.shared.request(
            endpoint: "auth/firebase/sync",
            method: .post,
            body: body,
            requiresAuth: false
        ) { [weak self] (result: Result<AuthResponse, APIError>) in
            switch result {
            case .success(let response):
                self?.handleAuthResponse(response) { _ in }
                self?.saveAuthProvider("firebase")
                completion(.success(response.user))
                
            case .failure(let error):
                let authError = self?.mapAPIErrorToAuthError(error, context: .login) ?? .unknown("Unknown error")
                completion(.failure(authError))
            }
        }
    }
    
    func verifyFirebaseToken(_ token: String, completion: @escaping (Result<User, Error>) -> Void) {
        let body: [String: Any] = ["firebaseIdToken": token]
        
        APIService.shared.request(
            endpoint: "auth/firebase/verify",
            method: .post,
            body: body,
            requiresAuth: false
        ) { [weak self] (result: Result<AuthResponse, APIError>) in
            switch result {
            case .success(let response):
                self?.handleAuthResponse(response) { _ in }
                self?.saveAuthProvider("firebase")
                completion(.success(response.user))
                
            case .failure(let error):
                let authError = self?.mapAPIErrorToAuthError(error, context: .login) ?? .unknown("Unknown error")
                completion(.failure(authError))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleAuthResponse(_ response: AuthResponse, completion: @escaping (Result<User, Error>) -> Void) {
        print("🔐 handleAuthResponse called, success: \(response.success)")
        
        if response.success {
            // Save tokens with expiration
            let expiration: Date?
            if let expiresIn = response.expiresIn {
                expiration = Date().addingTimeInterval(TimeInterval(expiresIn))
            } else {
                // Default to 24 hours if no expiration provided
                expiration = Date().addingTimeInterval(24 * 60 * 60)
            }
            saveToken(response.token, expiration: expiration)
            print("🔐 Token saved with expiration: \(expiration?.description ?? "none")")
            
            if let refreshToken = response.refreshToken {
                saveRefreshToken(refreshToken)
                APIService.shared.setRefreshToken(refreshToken)
                print("🔐 Refresh token saved")
            }
            saveUserId(response.user.id)
            print("🔐 User ID saved: \(response.user.id)")
            
            // Set token in API service
            APIService.shared.setAuthToken(response.token)
            
            // Save current user
            self._currentUser = response.user
            print("🔐 Current user set: \(response.user.displayName)")
            
            // Handle notifications setup for logged in user
            NotificationService.shared.handleUserLogin()
            
            // Notify auth state change
            print("🔐 About to notify auth state change - isLoggedIn: true")
            notifyAuthStateChange(isLoggedIn: true)
            
            // Register device token if available
            if let savedToken = UserDefaults.standard.string(forKey: "PushNotificationToken") {
                NotificationService.shared.registerDeviceToken(savedToken)
            }
            
            completion(.success(response.user))
        } else {
            print("🔐 Auth response not successful")
            completion(.failure(AuthError.unknown("Authentication failed")))
        }
    }
    
    private func clearLocalAuth() {
        clearToken()
        clearRefreshToken()
        clearUserId()
        clearAuthProvider()
        _currentUser = nil
        APIService.shared.clearTokens()
    }
    
    // MARK: - Auth State Listener
    
    func addAuthStateListener(id: String, listener: @escaping (Bool) -> Void) {
        authStateListeners[id] = listener
        // Immediately notify with current state
        listener(isLoggedIn)
    }
    
    func removeAuthStateListener(id: String) {
        authStateListeners.removeValue(forKey: id)
    }
    
    private func notifyAuthStateChange(isLoggedIn: Bool) {
        print("🔐 notifyAuthStateChange called with isLoggedIn: \(isLoggedIn)")
        print("🔐 Number of auth listeners: \(authStateListeners.count)")
        
        DispatchQueue.main.async {
            for (id, listener) in self.authStateListeners {
                print("🔐 Notifying listener: \(id)")
                listener(isLoggedIn)
            }
        }
    }
    
    // MARK: - Token Management
    
    private func saveToken(_ token: String, expiration: Date? = nil) {
        keychainService.saveAuthToken(token, expiration: expiration)
    }
    
    func getToken() -> String? {
        let token = keychainService.getAuthToken()
        // Removed verbose logging - this method is called very frequently
        return token
    }
    
    private func clearToken() {
        keychainService.clearAllTokens()
    }
    
    private func saveRefreshToken(_ token: String) {
        keychainService.saveRefreshToken(token)
    }
    
    private func clearRefreshToken() {
        keychainService.clearAllTokens()
    }
    
    private func saveUserId(_ userId: String) {
        keychainService.saveUserId(userId)
    }
    
    func getUserId() -> String? {
        let userId = keychainService.getUserId()
        // Removed verbose logging - this method is called very frequently
        return userId
    }
    
    private func clearUserId() {
        keychainService.clearAllTokens()
    }
    
    private func clearAppUserDefaults() {
        // Clear all app-specific UserDefaults that might contain user data
        let userDefaultsKeys = [
            "pendingDeepLink",
            "pendingConnectionInvite",
            "linkedInAuthState",
            "lastSuggestionsViewedTimestamp",
            "notificationPromptLastShown",
            "hasSeenTutorial",
            "hasCompletedOnboarding"
        ]
        
        for key in userDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        // Clear NetworkManager's pending connection invite
        NetworkManager.clearPendingConnectionInvite()
        
        print("🧹 AuthService: Cleared app-specific UserDefaults")
    }
    
    private func saveAuthProvider(_ provider: String) {
        keychainService.saveAuthProvider(provider)
    }
    
    func getAuthProvider() -> String? {
        return keychainService.getAuthProvider()
    }
    
    private func clearAuthProvider() {
        keychainService.clearAllTokens()
    }
    
    // MARK: - Error Mapping
    
    private enum AuthContext {
        case login
        case register
        case refreshToken
        case fetchUser
    }
    
    private func mapAPIErrorToAuthError(_ error: APIError, context: AuthContext) -> AuthError {
        switch error {
        case .httpError(let statusCode, let data):
            // Parse error message from response data if available
            if let data = data, let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                // Check for email verification error
                if errorResponse.message.lowercased().contains("email") && errorResponse.message.lowercased().contains("verif") {
                    return .emailNotVerified
                }
                
                switch statusCode {
                case 400:
                    // General validation error
                    return .unknown("Invalid request")
                case 401:
                    return .invalidCredentials
                case 403:
                    // Could be email not verified
                    if context == .login {
                        return .emailNotVerified
                    }
                    return .unknown("Forbidden")
                case 409:
                    if context == .register {
                        return .accountExists
                    }
                    return .unknown("Conflict")
                case 404:
                    return .accountNotFound
                default:
                    return .unknown("HTTP error: \(statusCode)")
                }
            }
            return .unknown(error.localizedDescription)
            
        case .unauthorized:
            return .tokenExpired
            
        case .noInternet, .requestFailed, .invalidURL, .invalidResponse, .decodingFailed, .duplicateRequest:
            return .networkError(error)
            
        case .serverError, .unknown:
            return .unknown(error.localizedDescription)
        }
    }
}

// MARK: - Response Models

struct AuthResponse: Decodable {
    let success: Bool
    let token: String
    let refreshToken: String?
    let user: User
    let expiresIn: Int? // Token expiration in seconds
}

struct UserResponse: Decodable {
    let success: Bool
    let user: User
}

struct ErrorResponse: Decodable {
    let success: Bool
    let message: String
}


struct VerificationStatusResponse: Decodable {
    let success: Bool
    let isVerified: Bool
}