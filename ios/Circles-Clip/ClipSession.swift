import Foundation
import Security

// The signed-in customer, remembered by the clip itself so the next scan at
// any store goes straight to their points (Wes, 2026-10-31: a store card, not
// a one-time signup). The clip's own keychain — clips can't share a keychain
// group with the app; the app gets the session through ClipHandoff instead.
struct ClipSession: Codable {
    let token: String
    let refreshToken: String?
    let expiresAt: Date
    let userId: String
    let displayName: String?
    let provider: String
    let email: String?
    /// Signed up with just an email: the app asks them to confirm it or set up Face ID
    let emailUnverified: Bool?

    private static let service = "com.favcircles.clip.session"
    private static let account = "current"

    var isExpired: Bool { expiresAt <= Date() }

    init(response: ClipAuthResponse, provider: String) {
        token = response.token
        refreshToken = response.refreshToken
        // Same fallback lifetime the app uses when expiresIn is missing (30d)
        expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 30 * 24 * 60 * 60))
        userId = response.user.id
        displayName = response.user.displayName
        self.provider = provider
        email = response.user.email
        emailUnverified = response.isEmailUnverified
    }

    /// The saved session, if any and not expired
    static var current: ClipSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let session = try? JSONDecoder().decode(ClipSession.self, from: data),
              !session.isExpired else { return nil }
        return session
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.clear()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
