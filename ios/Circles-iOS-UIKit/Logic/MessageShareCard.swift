import Foundation
import CoreLocation

/// A place, circle or location shared in a chat (2026-10-30: the chat's "+"
/// menu had Share Circle / Place / Location buttons wired to nothing). What
/// the sender puts in the message, and what a bubble reads back to draw a
/// tappable card. Pure: no UIKit, no services.
struct MessageShareCard: Equatable {
    enum Target: Equatable {
        /// A saved place (its page opens) — or, for an Apple Maps result
        /// nobody saved, just its coordinate (Maps opens)
        case place(id: String?, coordinate: CLLocationCoordinate2D?)
        case circle(id: String)
        case location(CLLocationCoordinate2D)

        static func == (a: Target, b: Target) -> Bool {
            switch (a, b) {
            case let (.place(i1, c1), .place(i2, c2)): return i1 == i2 && c1?.latitude == c2?.latitude && c1?.longitude == c2?.longitude
            case let (.circle(i1), .circle(i2)): return i1 == i2
            case let (.location(c1), .location(c2)): return c1.latitude == c2.latitude && c1.longitude == c2.longitude
            default: return false
            }
        }
    }

    let title: String
    let subtitle: String?
    /// A photo for the card; nil draws a map of `mapCoordinate` instead (or nothing)
    let imageURL: String?
    let mapCoordinate: CLLocationCoordinate2D?
    let target: Target
    /// "📍" / "⭕️" / "📌"
    let symbol: String

    static func == (a: MessageShareCard, b: MessageShareCard) -> Bool {
        a.title == b.title && a.subtitle == b.subtitle && a.imageURL == b.imageURL && a.target == b.target
            && a.mapCoordinate?.latitude == b.mapCoordinate?.latitude && a.mapCoordinate?.longitude == b.mapCoordinate?.longitude
    }

    // MARK: Sending: (content, metadata) for MessagingService.sendMessage

    /// `content` is the line the chat list and the push show.
    struct Outgoing {
        let type: MessageType
        let content: String
        let metadata: [String: Any]
    }

    static func place(id: String?, name: String, address: String?, photoURL: String?,
                      coordinate: CLLocationCoordinate2D?) -> Outgoing {
        var metadata: [String: Any] = ["placeName": name]
        if let id { metadata["placeId"] = id }
        if let address, !address.isEmpty { metadata["address"] = address }
        if let photoURL, !photoURL.isEmpty { metadata["photoUrl"] = photoURL }
        if let coordinate { metadata["lat"] = coordinate.latitude; metadata["lng"] = coordinate.longitude }
        return Outgoing(type: .placeShare, content: "📍 \(name)", metadata: metadata)
    }

    static func circle(id: String, name: String, placeCount: Int?, coverURL: String?) -> Outgoing {
        var metadata: [String: Any] = ["circleId": id, "circleName": name]
        if let placeCount { metadata["placeCount"] = placeCount }
        if let coverURL, !coverURL.isEmpty { metadata["coverUrl"] = coverURL }
        return Outgoing(type: .circleShare, content: "⭕️ \(name)", metadata: metadata)
    }

    static func location(_ coordinate: CLLocationCoordinate2D, address: String?) -> Outgoing {
        var metadata: [String: Any] = ["lat": coordinate.latitude, "lng": coordinate.longitude]
        if let address, !address.isEmpty { metadata["address"] = address }
        return Outgoing(type: .location, content: "📌 My location", metadata: metadata)
    }

    // MARK: Reading a received message

    init?(type: MessageType, metadata: [String: Any]?) {
        let m = metadata ?? [:]
        let coordinate = Self.coordinate(m)
        switch type {
        case .placeShare:
            guard let name = m["placeName"] as? String, !name.isEmpty else { return nil }
            self.init(title: name, subtitle: m["address"] as? String, imageURL: m["photoUrl"] as? String,
                      mapCoordinate: coordinate, target: .place(id: m["placeId"] as? String, coordinate: coordinate), symbol: "📍")
        case .circleShare:
            guard let id = m["circleId"] as? String, let name = m["circleName"] as? String else { return nil }
            let count = Self.int(m["placeCount"])
            self.init(title: name, subtitle: count.map { "\($0) \($0 == 1 ? "place" : "places")" }, imageURL: m["coverUrl"] as? String,
                      mapCoordinate: nil, target: .circle(id: id), symbol: "⭕️")
        case .location:
            guard let coordinate else { return nil }
            self.init(title: "My location", subtitle: m["address"] as? String, imageURL: nil,
                      mapCoordinate: coordinate, target: .location(coordinate), symbol: "📌")
        default:
            return nil
        }
    }

    private init(title: String, subtitle: String?, imageURL: String?, mapCoordinate: CLLocationCoordinate2D?,
                 target: Target, symbol: String) {
        self.title = title
        self.subtitle = subtitle.flatMap { $0.isEmpty ? nil : $0 }
        self.imageURL = imageURL.flatMap { $0.isEmpty ? nil : $0 }
        self.mapCoordinate = mapCoordinate
        self.target = target
        self.symbol = symbol
    }

    /// "📍 Pasta & Provisions\n1600 S Mint St…" for the bubble's caption
    var caption: String { [ "\(symbol) \(title)", subtitle ].compactMap { $0 }.joined(separator: "\n") }

    private static func coordinate(_ m: [String: Any]) -> CLLocationCoordinate2D? {
        guard let lat = double(m["lat"]), let lng = double(m["lng"]),
              (-90...90).contains(lat), (-180...180).contains(lng) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    private static func double(_ v: Any?) -> Double? { (v as? Double) ?? (v as? Int).map(Double.init) ?? (v as? String).flatMap(Double.init) }
    private static func int(_ v: Any?) -> Int? { (v as? Int) ?? (v as? Double).map { Int($0) } ?? (v as? String).flatMap(Int.init) }
}
