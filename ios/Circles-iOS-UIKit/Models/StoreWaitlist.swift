import Foundation

/// A store's waitlist (2026-11-09; server: services/waitlistService.js).
/// Customers: the setting as it reaches the place page and the App Clip.
struct StoreWaitlist: Codable, Equatable {
    var enabled: Bool
    /// The host's quoted wait per party ahead, in minutes
    var quoteMinutes: Int

    init(enabled: Bool = false, quoteMinutes: Int = 15) {
        self.enabled = enabled
        self.quoteMinutes = quoteMinutes
    }
}

/// One party in a store's line
struct WaitlistEntry: Codable, Equatable {
    let entryId: String
    let venueId: String
    let venueName: String?
    let placeId: String?
    let userId: String?
    let name: String?
    let partySize: Int
    /// waiting → notified → seated | left | removed | expired
    let status: String
    let joinedAt: String?
    let notifiedAt: String?
    /// 1-based place in line while open
    let position: Int?
    let estimateMinutes: Int?
    let holdMinutes: Int?
    let alreadyInLine: Bool?

    var isOpen: Bool { status == "waiting" || status == "notified" }
    var isCalled: Bool { status == "notified" }
}
