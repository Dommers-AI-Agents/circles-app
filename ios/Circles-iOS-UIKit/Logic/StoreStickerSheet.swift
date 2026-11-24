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

/// Coaster stickers: the generic "Join FavCircles" App Clip code on ¾ in
/// Avery 94102 squares, two per coaster (one for each side)
/// (`GET rewards/stickers/coasters`).
struct CoasterStickerSheet: Equatable {
    static let perSheet = 80
    static let maxCoasters = 1000
    /// One full sheet
    static let defaultCoasters = perSheet / 2

    var coasters: Int = defaultCoasters
    /// 1 is the top-left sticker; later positions skip stickers already used
    var startAt: Int = 1

    var queryParams: [String: String] {
        ["coasters": String(coasters), "startAt": String(startAt)]
    }

    var stickerCount: Int { coasters * 2 }

    var sheetCount: Int { (startAt - 1 + stickerCount + Self.perSheet - 1) / Self.perSheet }

    static func coasterCount(from text: String?) -> Int? {
        guard let value = Int((text ?? "").trimmingCharacters(in: .whitespaces)),
              (1...maxCoasters).contains(value) else { return nil }
        return value
    }

    static func startPosition(from text: String?) -> Int? {
        guard let value = Int((text ?? "").trimmingCharacters(in: .whitespaces)),
              (1...perSheet).contains(value) else { return nil }
        return value
    }

    var fileName: String {
        "FavCircles coaster stickers - \(coasters) \(coasters == 1 ? "coaster" : "coasters") - Avery 94102.pdf"
    }
}

/// Round 1½ in labels on Avery 8293 / Presta 94506 for picked stores:
/// - Totem QR labels for the Totem's base (`GET rewards/stickers/totem`): the
///   store's window code + `?t=totem`, the same link as the Totem's NFC
///   sticker (Wes, 2026-11-22: never 20 labels of one store).
/// - Table stickers (`GET rewards/stickers/table`): "Psst… regulars scan
///   this" in cream, the store's window code (Wes, 2026-11-24), `copies` of
///   each store's: one for every table. On clear labels (`stock`) the cream
///   is left out, so only the words and the code show on the table.
struct RoundLabelSheet: Equatable {
    enum Design: String, Equatable {
        case totem, table

        var endpoint: String { "rewards/stickers/\(rawValue)" }
        /// What the file and the prompts call them
        var noun: String { self == .totem ? "Totem labels" : "table stickers" }
    }

    /// The label sheet a print is for (table stickers only; a Totem label
    /// has no background to leave out)
    enum Stock: String, Equatable, CaseIterable {
        case white, clear

        /// What the sheet is sold as
        var sheetName: String { self == .white ? "Avery 8293" : "Avery 94506 clear" }
        /// The choice's row when asking which labels are in the printer
        var choiceTitle: String { self == .white ? "White labels (cream sticker)" : "Clear labels (only the print shows)" }
    }

    static let perSheet = 20
    static let maxStores = 100
    /// Most table stickers of one store, and most labels in one print (20 sheets)
    static let maxCopies = 100
    static let maxLabels = 400

    var design: Design
    /// Store ids in the order they were picked (that's the order they print)
    var venueIds: [String]
    /// 1 is the top-left label; later positions skip labels already used
    var startAt: Int = 1
    /// How many of each store's (table stickers only; a Totem has one base)
    var copies: Int = 1
    /// Which labels are in the printer (table stickers only)
    var stock: Stock = .white

    /// The stock the print uses: a Totem label is always the white sheet
    var printStock: Stock { design == .table ? stock : .white }

    var queryParams: [String: String] {
        var params = ["venueIds": venueIds.joined(separator: ","), "startAt": String(startAt)]
        if design == .table { params["copies"] = String(copies) }
        if printStock == .clear { params["stock"] = Stock.clear.rawValue }
        return params
    }

    var labelCount: Int { venueIds.count * (design == .table ? copies : 1) }

    /// Sheets the print takes from `startAt`
    var sheetCount: Int {
        guard !venueIds.isEmpty else { return 0 }
        return (startAt - 1 + labelCount + Self.perSheet - 1) / Self.perSheet
    }

    /// A typed number of each store's for `stores` picked stores, or nil when
    /// it isn't 1–100 or the print would pass 400 stickers
    static func copies(from text: String?, stores: Int) -> Int? {
        guard let value = Int((text ?? "").trimmingCharacters(in: .whitespaces)),
              (1...maxCopies).contains(value), stores * value <= maxLabels else { return nil }
        return value
    }

    /// The most of each store's that `stores` picked stores allow
    static func maxCopies(stores: Int) -> Int { max(1, min(maxCopies, maxLabels / max(stores, 1))) }

    /// A typed start position, or nil when it isn't 1–20
    static func startPosition(from text: String?) -> Int? {
        guard let value = Int((text ?? "").trimmingCharacters(in: .whitespaces)),
              (1...perSheet).contains(value) else { return nil }
        return value
    }

    var fileName: String {
        let each = design == .table && copies > 1 ? ", \(copies) each" : ""
        return "FavCircles \(design.noun) - \(venueIds.count) \(venueIds.count == 1 ? "store" : "stores")\(each) - \(printStock.sheetName).pdf"
    }
}

/// What the store picker on Sticker Venues is choosing stores for
enum StorePickPrint: Equatable {
    case windowStickers
    case totemLabels
    case tableStickers

    /// The round-label design, or nil for the square window stickers
    var roundDesign: RoundLabelSheet.Design? {
        switch self {
        case .windowStickers: return nil
        case .totemLabels: return .totem
        case .tableStickers: return .table
        }
    }

    var maxStores: Int { roundDesign == nil ? StoreStickerSheet.maxStores : RoundLabelSheet.maxStores }

    var perSheet: Int { roundDesign == nil ? StoreStickerSheet.perSheet : RoundLabelSheet.perSheet }

    /// The start-position prompt's title
    var startTitle: String { self == .totemLabels ? "Start at label #" : "Start at sticker #" }

    /// The "how many of each" prompt's message for `count` picked stores
    static func copiesMessage(count: Int) -> String {
        let whose = count == 1 ? "this store" : "each of the \(count) stores"
        return "One sticker for every table. How many for \(whose)? A sheet holds \(RoundLabelSheet.perSheet); up to \(RoundLabelSheet.maxCopies(stores: count))."
    }

    /// The "which labels" prompt's message (table stickers only)
    static let stockMessage = "Which labels are in the printer? On clear labels the cream is left out, so the code needs a light table to scan."

    /// The start-position prompt's message for `count` picked stores
    /// (`copies` of each on `stock`, table stickers only)
    func startMessage(count: Int, copies: Int = 1, stock: RoundLabelSheet.Stock = .white) -> String {
        switch self {
        case .windowStickers:
            return "\(count) \(count == 1 ? "sticker" : "stickers"), one per store, on Avery 22805. 1 is the top-left sticker; start later to skip ones already used."
        case .totemLabels:
            return "\(count) round \(count == 1 ? "label" : "labels"), one per store, on Avery 8293. 1 is the top-left label; start later to skip ones already used. Each opens the store like its Totem's NFC tag."
        case .tableStickers:
            let total = count * copies
            let split = copies == 1 ? "one per store" : (count == 1 ? "all for one store" : "\(copies) for each of \(count) stores")
            return "\(total) round \(total == 1 ? "sticker" : "stickers"), \(split), on \(stock.sheetName). 1 is the top-left sticker; start later to skip ones already used. Each says \"Psst… regulars scan this\" and opens the store; the store's name prints on the backing under it."
        }
    }
}
