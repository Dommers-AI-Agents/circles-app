import Foundation
import Security
import LocalAuthentication

class KeychainService {
    static let shared = KeychainService()

    private init() {}

    private let service = "com.favcircles.circles"

    // Account identifiers for different token types
    private let authTokenAccount = "authToken"
    private let refreshTokenAccount = "refreshToken"
    private let tokenExpirationAccount = "tokenExpiration"
    private let userIdAccount = "userId"
    private let authProviderAccount = "authProvider"

    // Account identifiers for saved credentials (with biometric protection)
    private let savedEmailAccount = "savedEmail"
    private let savedPasswordAccount = "savedPassword"
    
    // MARK: - Token Management
    
    func saveAuthToken(_ token: String, expiration: Date? = nil) {
        save(token, account: authTokenAccount)
        
        // Save expiration date if provided
        if let expiration = expiration {
            let expirationString = ISO8601DateFormatter().string(from: expiration)
            save(expirationString, account: tokenExpirationAccount)
        }
    }
    
    func getAuthToken() -> String? {
        return retrieve(account: authTokenAccount)
    }
    
    func saveRefreshToken(_ token: String) {
        save(token, account: refreshTokenAccount)
    }
    
    func getRefreshToken() -> String? {
        return retrieve(account: refreshTokenAccount)
    }
    
    func saveUserId(_ userId: String) {
        save(userId, account: userIdAccount)
    }
    
    func getUserId() -> String? {
        return retrieve(account: userIdAccount)
    }
    
    func saveAuthProvider(_ provider: String) {
        save(provider, account: authProviderAccount)
    }
    
    func getAuthProvider() -> String? {
        return retrieve(account: authProviderAccount)
    }
    
    func getTokenExpiration() -> Date? {
        guard let expirationString = retrieve(account: tokenExpirationAccount) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: expirationString)
    }
    
    func isTokenExpired() -> Bool {
        guard let expiration = getTokenExpiration() else {
            // If no expiration date is stored, assume token doesn't expire
            return false
        }
        return Date() >= expiration
    }
    
    func clearAllTokens() {
        delete(account: authTokenAccount)
        delete(account: refreshTokenAccount)
        delete(account: tokenExpirationAccount)
        delete(account: userIdAccount)
        delete(account: authProviderAccount)
    }

    // MARK: - Saved Credentials (with Biometric Protection)

    /// Save email and password with biometric protection
    func saveCredentials(email: String, password: String) {
        // Save email without biometric (we need to show it on login screen)
        save(email, account: savedEmailAccount)

        // Save password with biometric protection
        saveBiometricProtected(password, account: savedPasswordAccount)

        print("🔐 KeychainService: Saved credentials with biometric protection")
    }

    /// Retrieve saved email (no biometric required)
    func getSavedEmail() -> String? {
        return retrieve(account: savedEmailAccount)
    }

    /// Retrieve saved password (requires biometric authentication)
    func getSavedPassword(completion: @escaping (String?) -> Void) {
        retrieveBiometricProtected(account: savedPasswordAccount, completion: completion)
    }

    /// Check if credentials are saved
    func hasStoredCredentials() -> Bool {
        return getSavedEmail() != nil
    }

    /// Clear saved credentials
    func clearSavedCredentials() {
        delete(account: savedEmailAccount)
        delete(account: savedPasswordAccount)
        print("🔐 KeychainService: Cleared saved credentials")
    }

    // MARK: - Private Helper Methods
    
    private func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        // Delete any existing item
        delete(account: account)
        
        // Create query for adding new item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        // Add item to keychain
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            print("Error saving \(account) to keychain: \(status)")
        }
    }
    
    private func retrieve(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess,
           let data = dataTypeRef as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        
        return nil
    }
    
    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Biometric Protected Storage

    /// Save a value with biometric protection (Face ID / Touch ID required to retrieve)
    private func saveBiometricProtected(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete any existing item
        delete(account: account)

        // Create an access control object that requires biometric authentication
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet, // Requires biometric and invalidates if biometrics change
            &error
        ) else {
            print("❌ KeychainService: Failed to create access control: \(String(describing: error))")
            return
        }

        // Create query for adding new item with biometric protection
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl
        ]

        // Add item to keychain
        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            print("❌ KeychainService: Error saving biometric-protected \(account): \(status)")
        } else {
            print("✅ KeychainService: Successfully saved biometric-protected \(account)")
        }
    }

    /// Retrieve a biometric-protected value (requires Face ID / Touch ID)
    private func retrieveBiometricProtected(account: String, completion: @escaping (String?) -> Void) {
        let context = LAContext()
        context.localizedReason = "Authenticate to access your saved password"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        // Perform retrieval on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            var dataTypeRef: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

            DispatchQueue.main.async {
                if status == errSecSuccess,
                   let data = dataTypeRef as? Data,
                   let value = String(data: data, encoding: .utf8) {
                    print("✅ KeychainService: Successfully retrieved biometric-protected \(account)")
                    completion(value)
                } else {
                    print("❌ KeychainService: Failed to retrieve biometric-protected \(account): \(status)")
                    completion(nil)
                }
            }
        }
    }

    // MARK: - Migration from UserDefaults
    
    func migrateFromUserDefaults() {
        let userDefaults = UserDefaults.standard
        
        // Migrate auth token
        if let authToken = userDefaults.string(forKey: "authToken") {
            saveAuthToken(authToken)
            userDefaults.removeObject(forKey: "authToken")
        }
        
        // Migrate refresh token
        if let refreshToken = userDefaults.string(forKey: "refreshToken") {
            saveRefreshToken(refreshToken)
            userDefaults.removeObject(forKey: "refreshToken")
        }
        
        // Migrate user ID
        if let userId = userDefaults.string(forKey: "userId") {
            saveUserId(userId)
            userDefaults.removeObject(forKey: "userId")
        }
        
        // Migrate auth provider
        if let authProvider = userDefaults.string(forKey: "authProvider") {
            saveAuthProvider(authProvider)
            userDefaults.removeObject(forKey: "authProvider")
        }
        
        userDefaults.synchronize()
    }
}