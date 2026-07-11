import Foundation
import Security
import LocalAuthentication

class KeychainManager {
    static let shared = KeychainManager()

    private init() {}

    private let service = "com.favcircles.circles"
    // Plain credentials (remember-me prefill). Reads must NEVER trigger auth UI.
    private let userAccount = "userCredentials"
    // Biometric-protected copy used for re-authentication. Kept in a separate
    // account so plain prefill reads can't collide with the protected item and
    // fire an unexpected Face ID prompt.
    private let biometricAccount = "userCredentialsBiometric"
    
    // MARK: - Save Credentials
    func saveCredentials(email: String, password: String) {
        // Create a dictionary to store credentials
        let credentials: [String: String] = [
            "email": email,
            "password": password
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: credentials) else { return }

        // Replace only the plain item - don't touch the biometric copy
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Create query for adding new item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Add item to keychain
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            print("Error saving to keychain: \(status)")
        }
    }
    
    // MARK: - Retrieve Credentials
    /// Prompt-free read of the plain (remember-me) credentials. Guaranteed never
    /// to show auth UI: legacy installs may still have a biometric-protected item
    /// under this account, and kSecUseAuthenticationUIFail makes that read fail
    /// silently instead of surprising the user with a Face ID prompt.
    func retrieveCredentials() -> (email: String, password: String)? {
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        return decodeCredentials(matching: query)
    }

    /// Reads the biometric-protected credentials, presenting a single system
    /// Face ID / Touch ID prompt. Blocks the calling thread while the prompt is
    /// up - call from a background queue. Falls back to the legacy plain-account
    /// item for users who enabled biometric before the accounts were split.
    func retrieveCredentialsWithBiometric(reason: String) -> (email: String, password: String)? {
        let context = LAContext()
        context.localizedReason = reason

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: biometricAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        if let credentials = decodeCredentials(matching: query) {
            return credentials
        }

        // Legacy fallback: biometric item stored under the plain account
        query[kSecAttrAccount as String] = userAccount
        return decodeCredentials(matching: query)
    }

    private func decodeCredentials(matching query: [String: Any]) -> (email: String, password: String)? {
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess,
           let data = dataTypeRef as? Data,
           let credentialsDict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let email = credentialsDict["email"],
           let password = credentialsDict["password"] {
            return (email: email, password: password)
        }

        return nil
    }

    // MARK: - Delete Credentials
    func deleteCredentials() {
        for account in [userAccount, biometricAccount] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
    
    // MARK: - Check if credentials exist
    func hasStoredCredentials() -> Bool {
        return retrieveCredentials() != nil
    }
    
    // MARK: - Biometric Authentication Support
    func saveCredentialsWithBiometric(email: String, password: String) {
        // This version requires biometric authentication to access
        let credentials: [String: String] = [
            "email": email,
            "password": password
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: credentials) else { return }

        // Replace only the biometric copy - the plain remember-me item (if the
        // user opted into it) stays intact for prompt-free prefill
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: biometricAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Create access control with biometric requirement
        var error: Unmanaged<CFError>?
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        )

        guard let accessControl = access else {
            print("Failed to create access control")
            return
        }

        // Create query for adding new item with biometric protection
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: biometricAccount,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            print("Error saving to keychain with biometric: \(status)")
        }
    }
}