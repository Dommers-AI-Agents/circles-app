import Foundation
import Security

/// Stores the user's Cactus wallet secret phrase in the iCloud Keychain
/// (kSecAttrSynchronizable): encrypted by Apple, synced across the user's
/// devices, survives a lost phone. FavCircles' servers never see it — this is
/// device/Apple-account storage only, which is what keeps the "we can't move
/// or take your coins" promise literally true.
enum WalletPhraseStore {

    private static let service = "com.favcircles.circles.cactus-wallet"

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]
    }

    /// Save (or replace) the phrase for a user. Returns false on keychain
    /// failure — callers must NOT proceed as if the phrase were backed up.
    @discardableResult
    static func save(mnemonic: String, account: String) -> Bool {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        var attributes = baseQuery(account: account)
        attributes[kSecValueData as String] = Data(mnemonic.utf8)
        // WhenUnlocked (not ThisDeviceOnly) — ThisDeviceOnly items refuse to
        // sync to iCloud, which would defeat the lost-phone story.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
