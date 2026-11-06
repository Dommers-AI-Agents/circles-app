import Foundation

/// The words around sending a delivery receipt for points. Pure.
enum ReceiptCopy {
    struct Check: Equatable {
        let ok: Bool
        let text: String
    }

    /// The store card's row (2026-11-06)
    static let entryTitle = "Ordered for delivery? Send your receipt"

    static func entryDetail(mode: String?, venueName: String) -> String {
        mode == "auto" ? "Points for your DoorDash or Uber Eats order, right away"
                       : "\(venueName) gives points for delivery orders too"
    }

    /// What the phone found, line by line
    static func checks(_ reading: ReceiptReading, venueName: String, now: Date = Date()) -> [Check] {
        var out: [Check] = []
        out.append(reading.storeNameFound
            ? Check(ok: true, text: reading.storeLine ?? venueName)
            : Check(ok: false, text: "Can't find \(venueName) on it"))
        if let date = reading.orderDate {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            out.append(ReceiptReader.isTooOld(date, now: now)
                ? Check(ok: false, text: "Ordered \(f.string(from: date)): over a week ago")
                : Check(ok: true, text: "Ordered \(f.string(from: date))"))
        } else {
            out.append(Check(ok: false, text: "No order date found"))
        }
        out.append(reading.orderNumber.map { Check(ok: true, text: "Order #\($0)") }
            ?? Check(ok: false, text: "No order number found"))
        return out
    }

    /// Under the checks, before Send
    static func sendNote(mode: String?, venueName: String, allOK: Bool) -> String {
        if mode == "auto" && allOK { return "Everything checks out. Your points arrive as soon as you send it." }
        if mode == "auto" { return "\(venueName) will take a look, since not everything could be read. You'll get a notification." }
        return "\(venueName) looks at each receipt and sends your points. You'll get a notification."
    }

    static func sentMessage(_ result: ReceiptSubmitResult, venueName: String) -> (title: String, message: String) {
        if result.status == "approved", let points = result.points {
            let balance = result.venueBalance.map { " You have \($0) points there." } ?? ""
            return ("+\(points) points", "You earned \(points) points at \(venueName) for your delivery order.\(balance)")
        }
        return ("Sent to \(venueName)", "You'll get a notification when they answer.")
    }
}
