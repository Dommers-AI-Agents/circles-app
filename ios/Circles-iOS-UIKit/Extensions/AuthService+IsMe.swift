import Foundation

extension AuthService {
    /// Whether `userId` is the signed-in person. Checks the keychain's id
    /// too, so it works before the profile has loaded — comparing only with
    /// `currentUser?.id` showed "Follow" on your own moments while it was
    /// still nil (Wes, 2026-10-09).
    func isMe(_ userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return IDNormalizer.isSameUser(userId, getUserId()) || IDNormalizer.isSameUser(userId, currentUser?.id)
    }
}
