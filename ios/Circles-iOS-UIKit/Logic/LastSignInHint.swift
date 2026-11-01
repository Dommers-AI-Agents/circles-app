import Foundation

/// The account last signed in on this phone, kept through logout so the
/// login screen can say "Welcome back" and how they signed in last time
/// (Wes, 2026-11-01: Brittany kept looking for a password her Google account
/// never had). Device-only; "Not you?" or deleting the account forgets it.
struct LastSignInHint: Equatable {
    enum Method: Equatable {
        case google, apple, passkey, password, other
    }

    let userId: String
    let email: String?
    let displayName: String?
    let photoURL: String?
    let method: Method

    /// From the dictionary AuthService keeps (`lastAccountOnDevice`)
    init?(stored: [String: Any]?) {
        guard let stored, let id = stored["id"] as? String, !id.isEmpty else { return nil }
        userId = id
        email = (stored["email"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        displayName = (stored["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        photoURL = (stored["photo"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        method = Self.method(stored["method"] as? String)
    }

    /// The keychain's provider names ("google", "apple", "passkey", "email",
    /// "firebase") as the login screen talks about them
    static func method(_ provider: String?) -> Method {
        switch provider?.lowercased() {
        case "google": return .google
        case "apple": return .apple
        case "passkey": return .passkey
        case "email", "firebase", "manual", "password": return .password
        default: return .other
        }
    }

    /// Apple's private relay addresses mean nothing to the person reading them
    var isHiddenEmail: Bool { email?.lowercased().hasSuffix("@privaterelay.appleid.com") == true }

    /// "Brittany"
    var firstName: String? { displayName?.split(separator: " ").first.map(String.init) }

    /// "Last time you used Google · brittany@gmail.com"
    var lastTimeLine: String {
        let how: String
        switch method {
        case .google: how = "Google"
        case .apple: how = "Apple"
        case .passkey: how = "Face ID"
        case .password: how = "your email and password"
        case .other: how = "this account"
        }
        let who = isHiddenEmail ? "(hidden email)" : email
        return ["Last time you used \(how)", who].compactMap { $0 }.joined(separator: " · ")
    }
}
