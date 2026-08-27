import Foundation

/// The JSON contract between the app (writer) and the home-screen widget
/// (reader), handed through the App Group container — same channel as the App
/// Clip's auth mailbox (ClipHandoff). The widget process never talks to the
/// network; the app refreshes this file on launch and on backgrounding.
///
/// This file is compiled into BOTH the app target and Circles-Widget, so keep
/// it dependency-free (Foundation only) and Codable-stable.
struct WidgetSnapshot: Codable {
    struct Entry: Codable {
        /// Save-record id for the circles://place/<id> deep link (nil = row
        /// just opens the app).
        let placeId: String?
        /// Place name.
        let title: String
        /// "Joey · Pizza Spots" — who saved it, and where.
        let subtitle: String
        let timestamp: Date
    }

    let generatedAt: Date
    /// Newest first. The medium widget shows the first 3.
    let entries: [Entry]
    /// Total FavCoins, for the small widget's footer. Nil = don't show.
    let coinBalance: Double?
}

enum WidgetSnapshotStore {
    static let appGroupId = "group.com.favcircles.circles"
    static let fileName = "widget-snapshot.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    /// Sign-out: the widget must not keep showing the account's network data.
    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
