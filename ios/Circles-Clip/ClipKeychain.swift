import Foundation
import Security

// One-shot credential "mailbox" for the clip → full app handoff.
//
// The clip writes tokens ONLY into the shared keychain access group; the full
// app's KeychainService.adoptClipCredentialsIfPresent() copies them into its
// normal (default-group) storage on first launch and clears the mailbox.
// Account names deliberately match KeychainService so adoption is a 1:1 copy.
enum ClipKeychain {

    // Team ID prefix + shared group — must match keychain-access-groups in both
    // Circles-Clip.entitlements and the parent app's entitlements.
    static let accessGroup = "67E8B4E8HV.com.favcircles.circles.shared"
    static let service = "com.favcircles.circles"

    enum Account: String {
        case authToken
        case refreshToken
        case tokenExpiration
        case userId
        case authProvider
        case clipHandledStickerCode  // scan succeeded in the clip — full app must NOT redeem again
        case clipPendingStickerCode  // scan failed in the clip — full app should redeem it
    }

    static func storeAuthHandoff(response: ClipAuthResponse, provider: String) {
        save(response.token, account: .authToken)
        if let refreshToken = response.refreshToken {
            save(refreshToken, account: .refreshToken)
        }
        // Same fallback lifetime the app uses when expiresIn is missing (30d)
        let lifetime = response.expiresIn ?? 30 * 24 * 60 * 60
        let expiration = Date().addingTimeInterval(TimeInterval(lifetime))
        save(ISO8601DateFormatter().string(from: expiration), account: .tokenExpiration)
        save(response.user.id, account: .userId)
        save(provider, account: .authProvider)
    }

    static func save(_ value: String, account: Account) {
        guard let data = value.data(using: .utf8) else { return }
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func retrieve(account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: Account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecAttrAccessGroup as String: accessGroup
        ]
        SecItemDelete(query as CFDictionary)
    }
}
