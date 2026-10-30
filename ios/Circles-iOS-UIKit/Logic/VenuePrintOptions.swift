import Foundation

/// What a store can print for one of its QR codes, and at what size. Pure
/// choices: the backend (`GET rewards/venues/:id/print`) draws the PDF at real
/// size, so a 3 in code prints at 3 in instead of filling the sheet.
enum VenuePrintKind: String, CaseIterable {
    /// Scan-to-save code for the front window (free owner tier)
    case window
    /// Earn-points-every-visit code for the register (Business)
    case register

    var screenTitle: String {
        switch self {
        case .window: return "Window QR"
        case .register: return "Register QR"
        }
    }
}

enum VenuePrintFormat: String, CaseIterable {
    case sign
    case tent
    case smallTent
    case card
    /// A sheet of 1½ in square stickers (Avery 22805), the code alone: covers
    /// the old App Store code on a printed FavCircles window sticker
    case stickers

    var title: String {
        switch self {
        case .sign: return "Sign"
        case .tent: return "Table tent"
        case .smallTent: return "Small tent"
        case .card: return "Counter card"
        case .stickers: return "Stickers"
        }
    }

    /// What comes out of the printer, in plain words
    var paperNote: String {
        switch self {
        case .sign: return "One letter page, portrait. Tape it in the window or on the counter."
        case .tent: return "One letter page. Fold it in half along the dashed line and it stands on its own (11 × 4¼ in faces)."
        case .smallTent: return "One letter page. Cut along the dotted lines, fold in the middle: a 4 × 5½ in tent for a table or the register."
        case .card: return "A 4 × 6 in card. Fits a photo frame or an acrylic stand. On letter paper, cut it out."
        case .stickers: return "24 stickers on an Avery 22805 sheet (1½ in squares). Print at Actual size; try one on plain paper first. One covers the code on a FavCircles window sticker."
        }
    }

    /// The biggest code the face has room for, in inches
    var maxQRInches: Double {
        switch self {
        case .sign: return 4
        case .tent: return 3.5
        case .smallTent: return 3
        case .card: return 3.5
        case .stickers: return Self.stickerQRInches
        }
    }

    /// The sticker sets the code's size; the size choice doesn't apply
    var hasQRSizeChoice: Bool { self != .stickers }

    static let stickerQRInches = 1.25
}

enum VenuePrintQRSize: String, CaseIterable {
    case small, medium, large

    var inches: Double {
        switch self {
        case .small: return 1
        case .medium: return 3
        case .large: return 4
        }
    }

    var title: String { "\(Int(inches)) in" }
}

struct VenuePrintOptions: Equatable {
    var kind: VenuePrintKind
    // The small table tent with a 2 in code unless they pick otherwise (Wes, 2026-10-30)
    var format: VenuePrintFormat = .smallTent
    var qrSize: VenuePrintQRSize = .small

    var queryParams: [String: String] {
        ["kind": kind.rawValue, "format": format.rawValue, "qr": qrSize.rawValue]
    }

    /// The code's printed size once the face has had its say
    var effectiveQRInches: Double {
        format.hasQRSizeChoice ? min(qrSize.inches, format.maxQRInches) : VenuePrintFormat.stickerQRInches
    }

    /// One line for the sheet: paper plus the code's real printed size
    var summary: String {
        let inches = effectiveQRInches
        guard format.hasQRSizeChoice else { return format.paperNote }
        let size = inches == inches.rounded() ? "\(Int(inches))" : String(format: "%.1f", inches)
        let clamped = inches < qrSize.inches ? " (the most this layout fits)" : ""
        return "\(format.paperNote) The code prints \(size) in wide\(clamped)."
    }

    /// The file the share sheet shows, e.g. "Tommys Tavern - window table tent - 3in QR.pdf"
    func fileName(storeName: String) -> String {
        let safe = storeName.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" }
            .map { Character($0) }
        let name = String(safe).trimmingCharacters(in: .whitespaces)
        let kindWord = kind == .window ? "window" : "register"
        if format == .stickers { return "\(name.isEmpty ? "store" : name) - \(kindWord) stickers - Avery 22805.pdf" }
        return "\(name.isEmpty ? "store" : name) - \(kindWord) \(format.title.lowercased()) - \(Int(qrSize.inches))in QR.pdf"
    }
}
