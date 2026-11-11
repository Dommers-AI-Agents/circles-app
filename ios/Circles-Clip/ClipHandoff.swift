import Foundation

// One-shot credential "mailbox" for the clip → full app handoff.
//
// App Clips may NOT hold the keychain-access-groups entitlement (the installer
// rejects it), so the handoff rides Apple's documented clip→app channel
// instead: a shared App Group container. The clip writes one JSON file with
// complete file protection; the full app's
// KeychainService.adoptClipCredentialsIfPresent() moves the tokens into its
// normal keychain storage on first launch and deletes the file.
enum ClipHandoff {

    // Must match com.apple.security.application-groups in BOTH
    // Circles-Clip.entitlements and the parent app's entitlements.
    static let appGroupId = "group.com.favcircles.circles"
    static let fileName = "clip-auth-handoff.json"

    struct Payload: Codable {
        var authToken: String
        var refreshToken: String?
        var tokenExpiration: String? // ISO8601
        var userId: String
        var authProvider: String
        var handledStickerCode: String?  // clip redeemed this code — full app must NOT redeem again
        var pendingStickerCode: String?  // clip failed to redeem — full app should run the pending flow
        var welcome: Welcome?            // the store and what they earned, for the app's first launch
        var accountEmail: String?        // with emailUnverified: the app asks to confirm it or set up Face ID
        var emailUnverified: Bool?
        /// The clip made this account just now: the app runs its first run
        /// (name → favorite spot → people → tour) even with no store (2026-11-09)
        var isNewSignIn: Bool? = nil
        /// A Scan Action QR (2026-11-11) the app opens on first launch: the
        /// places the clip saved, or the guide / store setup it couldn't run
        var pendingScanCode: String? = nil
    }

    /// What the full app's first launch shows: the store's page with a
    /// welcome — points earned, how to keep earning, what the points buy
    struct Welcome: Codable {
        let code: String
        let kind: String?
        let venue: ClipVenue
        let awardedPoints: Int?
        let venueBalance: Int?
        let earnRate: Int?
        let offers: [ClipOffer]
        let nextRewardLine: String?
        let alreadySaved: Bool?
        /// The clip saved the store (2026-11-01): the app opens on it, saved
        var saved: Bool? = nil
        var savedCircleId: String? = nil
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(fileName)
    }

    static func storeAuthHandoff(session: ClipSession, isNewSignIn: Bool = false) {
        let payload = Payload(
            authToken: session.token,
            refreshToken: session.refreshToken,
            tokenExpiration: ISO8601DateFormatter().string(from: session.expiresAt),
            userId: session.userId,
            authProvider: session.provider,
            handledStickerCode: nil,
            pendingStickerCode: nil,
            welcome: nil,
            accountEmail: session.email,
            emailUnverified: session.emailUnverified,
            isNewSignIn: isNewSignIn
        )
        write(payload)
    }

    static func markStickerHandled(_ code: String, welcome: Welcome? = nil) {
        guard var payload = read() else { return }
        payload.handledStickerCode = code
        payload.welcome = welcome
        payload.pendingStickerCode = nil
        write(payload)
    }

    static func markStickerPending(_ code: String) {
        guard var payload = read() else { return }
        payload.pendingStickerCode = code
        payload.handledStickerCode = nil
        write(payload)
    }

    /// The app opens this Scan Action QR when it first launches
    static func markScanPending(_ code: String) {
        guard var payload = read() else { return }
        payload.pendingScanCode = code
        write(payload)
    }

    static func read() -> Payload? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    private static func write(_ payload: Payload) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}
