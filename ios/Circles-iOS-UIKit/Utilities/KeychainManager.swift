import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    private let service = "com.favcircles.circles"
    private let userAccount = "userCredentials"
    
    // MARK: - Save Credentials
    func saveCredentials(email: String, password: String) {
        // Create a dictionary to store credentials
        let credentials: [String: String] = [
            "email": email,
            "password": password
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: credentials) else { return }
        
        // Delete any existing item
        deleteCredentials()
        
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
    func retrieveCredentials() -> (email: String, password: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userAccount
        ]
        
        SecItemDelete(query as CFDictionary)
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
        
        // Delete any existing item
        deleteCredentials()
        
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
            kSecAttrAccount as String: userAccount,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            print("Error saving to keychain with biometric: \(status)")
        }
    }
}