import Foundation

/// What a person sees when something fails (Wes, 2026-10-30: "change all user
/// facing error messages to something like 'Oops something went wrong. Please
/// try again' where appropriate"). One rule for every alert:
/// - a connection problem says so, in plain words;
/// - a message the server wrote for people ("This store isn't taking orders
///   right now") is kept, because it tells them what to do;
/// - anything technical (decoding, status codes, "The operation couldn't be
///   completed", a server's "Failed to process scan") becomes the friendly line.
enum FriendlyError {
    static let title = "Oops"
    static let generic = "Oops, something went wrong. Please try again."
    static let offline = "Oops, we couldn't connect. Check your connection and try again."
    static let signIn = "Please sign in again, then try once more."

    static func message(for error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .noInternet: return offline
            case .unauthorized: return signIn
            case .rateLimited: return api.errorDescription ?? generic
            case .duplicateRequest: return generic
            case .requestFailed(let inner): return message(for: inner)
            case .httpError(let status, _):
                if status >= 500 { return generic }
                if status == 401 { return signIn }
                if status == 429 { return "You're going a bit fast. Please wait a moment and try again." }
                if let server = api.serverMessage, !isTechnical(server) { return polished(server) }
                return generic
            default: return generic
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return offline }
        return clean(error.localizedDescription)
    }

    /// A message string some screen built: kept unless it's technical.
    static func clean(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return generic }
        if looksOffline(t) { return offline }
        return isTechnical(t) ? generic : t
    }

    static func looksOffline(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("offline") || t.contains("timed out") || t.contains("network connection was lost")
            || t.contains("can't reach favcircles") || t.contains("not connected to the internet")
    }

    /// Wording no one should see: system codes, parser errors, server fallbacks.
    static func isTechnical(_ text: String) -> Bool {
        let t = text.lowercased()
        let markers = [
            "operation couldn", "operation could not", "error domain", "nserror", "nsurl", "error code",
            "(error ", "status code", "decod", "keynotfound", "datacorrupted", "the data couldn",
            "request failed", "invalid server response", "server error", "unknown error", "internal",
            "undefined", "null", "exception", "econn", "failed to ", "invalid url", "json", "http",
            "permission_denied", "unauthenticated", "firestore", "firebase"
        ]
        return markers.contains { t.contains($0) }
    }

    private static func polished(_ s: String) -> String {
        var p = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = p.first else { return generic }
        p = first.uppercased() + p.dropFirst()
        if !(p.hasSuffix(".") || p.hasSuffix("!") || p.hasSuffix("?")) { p += "." }
        return p
    }
}
