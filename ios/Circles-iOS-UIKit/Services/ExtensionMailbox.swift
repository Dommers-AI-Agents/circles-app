import Foundation

// The App Group file channel between the main app and its extensions —
// the same mechanism as the App Clip's ClipHandoff, in both directions:
//
//   ExtensionAuthMailbox  (app → extension): the app mirrors the session
//     token so the Share Extension can call the API. The main keychain has no
//     access group, so extensions can't read it directly; the mirror is
//     rewritten on every token change and removed on logout.
//
//   PendingShareMailbox   (extension → app): a share the extension couldn't
//     complete (logged out, offline) parks here; the app drains it on launch
//     and routes into the normal add-place flow.
//
// This file is compiled into BOTH the app target and Circles-Share — keep it
// Foundation-only.

enum ExtensionAuthMailbox {
    static let appGroupId = "group.com.favcircles.circles"
    static let fileName = "extension-auth.json"

    struct Payload: Codable {
        var authToken: String
        var tokenExpiration: String?  // ISO8601
        var userId: String?
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(fileName)
    }

    static func write(_ payload: Payload) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func read() -> Payload? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// extension → app: "the user asked to see this place" — written when the
/// share extension's "View in FavCircles" hand-off can't open the app
/// directly (extensionContext.open is unreliable for share extensions). The
/// app drains it on launch and navigates straight to the place.
enum PendingOpenPlaceMailbox {
    static let fileName = "pending-open-place.json"

    struct Payload: Codable {
        var placeId: String
        var createdAt: Date
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ExtensionAuthMailbox.appGroupId)?
            .appendingPathComponent(fileName)
    }

    static func write(placeId: String) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(Payload(placeId: placeId, createdAt: Date())) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// One-shot: reading removes the file. Stale requests (>1h) are dropped —
    /// auto-navigating to a place the user shared yesterday would be jarring.
    static func take() -> String? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              Date().timeIntervalSince(payload.createdAt) < 3600 else { return nil }
        return payload.placeId
    }
}

/// extension → app: "the user hit a plan limit and tapped Upgrade" — the app
/// presents the paywall on next launch (the parked share then finishes via
/// the normal drain → prefilled Add Place underneath the paywall sheet).
enum PendingUpgradeMailbox {
    static let fileName = "pending-upgrade.json"

    struct Payload: Codable { var createdAt: Date }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ExtensionAuthMailbox.appGroupId)?
            .appendingPathComponent(fileName)
    }

    static func write() {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(Payload(createdAt: Date())) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// One-shot; stale (>1h) requests are dropped.
    static func take() -> Bool {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return false }
        try? FileManager.default.removeItem(at: url)
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return false }
        return Date().timeIntervalSince(payload.createdAt) < 3600
    }
}

enum PendingShareMailbox {
    static let appGroupId = "group.com.favcircles.circles"
    static let fileName = "pending-share.json"

    struct Payload: Codable {
        /// The shared URL, if the share carried one (Google Maps link, web page).
        var sharedURL: String?
        /// The shared text (or page title) — the add-place search seed.
        var sharedText: String?
        var createdAt: Date
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(fileName)
    }

    static func write(_ payload: Payload) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// One-shot: reading removes the file.
    static func take() -> Payload? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}
