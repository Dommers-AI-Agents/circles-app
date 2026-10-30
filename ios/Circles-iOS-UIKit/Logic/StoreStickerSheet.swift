import Foundation

/// Many stores' window codes on one Avery 22805 sheet, one sticker each with
/// the store's name under it (`GET rewards/stickers/print`). Pure choices;
/// the server draws the PDF.
struct StoreStickerSheet: Equatable {
    static let perSheet = 24
    static let maxStores = 96

    /// Store ids in the order they were picked (that's the order they print)
    var venueIds: [String]
    /// 1 is the top-left sticker; later positions skip stickers already used
    var startAt: Int = 1

    var queryParams: [String: String] {
        ["venueIds": venueIds.joined(separator: ","), "kind": "window", "startAt": String(startAt)]
    }

    /// Sheets the print takes from `startAt`
    var sheetCount: Int {
        guard !venueIds.isEmpty else { return 0 }
        return (startAt - 1 + venueIds.count + Self.perSheet - 1) / Self.perSheet
    }

    /// A typed start position, or nil when it isn't 1–24
    static func startPosition(from text: String?) -> Int? {
        guard let value = Int((text ?? "").trimmingCharacters(in: .whitespaces)),
              (1...perSheet).contains(value) else { return nil }
        return value
    }

    /// The pick list after tapping a store: picked stores keep their order
    static func toggled(_ ids: [String], _ id: String) -> [String] {
        ids.contains(id) ? ids.filter { $0 != id } : ids + [id]
    }

    var fileName: String {
        "FavCircles stickers - \(venueIds.count) \(venueIds.count == 1 ? "store" : "stores") - Avery 22805.pdf"
    }
}
