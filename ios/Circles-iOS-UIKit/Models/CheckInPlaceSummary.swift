import Foundation

/// One place you've checked in at, from GET /check-ins/me/places (the
/// "My check-ins" screen, 2026-11-09). Only ever the viewer's own.
struct CheckInPlaceSummary: Decodable, Equatable {
    let globalPlaceId: String
    /// The save record the latest check-in was at, when there was one
    let placeId: String?
    let name: String
    let address: String?
    let category: String?
    let photoUrl: String?
    let count: Int
    let importedCount: Int?
    let firstCheckInAt: Date?
    let lastCheckInAt: Date?
    /// Check-ins here in the last `recentDays` (the list's header says how many days)
    let recentCount: Int

    /// The same shape the place page's caption is built from
    var stats: CheckInStats {
        CheckInStats(count: count, firstCheckInAt: firstCheckInAt, lastCheckInAt: lastCheckInAt, importedCount: importedCount)
    }
}

struct CheckInPlacesPage: Decodable, Equatable {
    let total: Int
    let places: Int
    let recent: Int
    let recentDays: Int
    let items: [CheckInPlaceSummary]
}
