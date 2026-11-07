import Foundation

/// Which account a passkey belongs to, and what it's called on the device.
/// Wes, 2026-11-07: an "offer Face ID" note left over from a tester account
/// fired after he signed in as himself, and the passkey was added to his
/// account under the tester's email — Face ID then "read back" the wrong
/// account. The server decides the account, so it names the passkey too, and
/// a remembered offer only counts for the account it was made for.
enum PasskeyAccountMatch {

    /// The name the device saves: the server's (the account the passkey is
    /// actually added to), the app's guess only when the server sent none
    static func label(serverName: String?, fallback: String) -> String {
        let server = serverName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return server.isEmpty ? fallback : server
    }

    /// A stashed "offer Face ID to <email>" is for the signed-in account only
    static func isForSignedInAccount(stashedEmail: String?, signedInEmail: String?) -> Bool {
        func normal(_ s: String?) -> String { s?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" }
        let stashed = normal(stashedEmail), current = normal(signedInEmail)
        return !stashed.isEmpty && stashed == current
    }
}
