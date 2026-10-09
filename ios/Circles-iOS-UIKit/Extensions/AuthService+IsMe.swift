import Foundation

extension AuthService {
    /// Whether `userId` is the signed-in person. Matches across the ID
    /// formats an account can carry (IDNormalizer), and works before the
    /// profile has loaded (the keychain's id) — an exact compare against
    /// `currentUser?.id` showed "Follow" on your own moments (Wes, 2026-10-09).
    func isMe(_ userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return IDNormalizer.isSameUser(userId, getUserId()) || IDNormalizer.isSameUser(userId, currentUser?.id)
    }
}
