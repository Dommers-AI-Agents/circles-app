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
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(fileName)
    }

    static func storeAuthHandoff(response: ClipAuthResponse, provider: String) {
        // Same fallback lifetime the app uses when expiresIn is missing (30d)
        let lifetime = response.expiresIn ?? 30 * 24 * 60 * 60
        let expiration = Date().addingTimeInterval(TimeInterval(lifetime))
        let payload = Payload(
            authToken: response.token,
            refreshToken: response.refreshToken,
            tokenExpiration: ISO8601DateFormatter().string(from: expiration),
            userId: response.user.id,
            authProvider: provider,
            handledStickerCode: nil,
            pendingStickerCode: nil
        )
        write(payload)
    }

    static func markStickerHandled(_ code: String) {
        guard var payload = read() else { return }
        payload.handledStickerCode = code
        payload.pendingStickerCode = nil
        write(payload)
    }

    static func markStickerPending(_ code: String) {
        guard var payload = read() else { return }
        payload.pendingStickerCode = code
        payload.handledStickerCode = nil
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
