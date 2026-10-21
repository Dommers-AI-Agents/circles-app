import Foundation

/// A store's full menu (2026-10-20): sections of items, usually filled by
/// scanning the printed menu. Prices are kept exactly as printed ("12",
/// "$12.50", "MP", "glass 10 · bottle 36"). The featured items on the
/// storefront stay the highlights; this is the whole thing.
struct StorefrontMenu: Codable, Equatable {
    var sections: [StorefrontMenuSection]
    /// "scan" or "manual"
    var source: String?
    var updatedAt: String?

    init(sections: [StorefrontMenuSection] = [], source: String? = nil, updatedAt: String? = nil) {
        self.sections = sections; self.source = source; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey { case sections, source, updatedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sections = (try? c.decode([StorefrontMenuSection].self, forKey: .sections)) ?? []
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    var itemCount: Int { sections.reduce(0) { $0 + $1.items.count } }
    var isEmpty: Bool { itemCount == 0 }

    var asBody: [String: Any] {
        [
            "source": source ?? "manual",
            "sections": sections.map { section -> [String: Any] in
                [
                    "id": section.id,
                    "name": section.name,
                    "items": section.items.map { item -> [String: Any] in
                        ["id": item.id, "name": item.name, "price": item.price ?? NSNull(),
                         "description": item.description ?? NSNull(), "tags": item.tags]
                    }
                ]
            }
        ]
    }
}

struct StorefrontMenuSection: Codable, Equatable {
    var id: String
    var name: String
    var items: [StorefrontMenuItem]

    init(id: String = "s_\(UUID().uuidString.prefix(8))", name: String, items: [StorefrontMenuItem] = []) {
        self.id = id; self.name = name; self.items = items
    }

    enum CodingKeys: String, CodingKey { case id, name, items }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? "s_\(UUID().uuidString.prefix(8))"
        name = (try? c.decode(String.self, forKey: .name)) ?? "Menu"
        items = (try? c.decode([StorefrontMenuItem].self, forKey: .items)) ?? []
    }
}

struct StorefrontMenuItem: Codable, Equatable {
    var id: String
    var name: String
    var price: String?
    var description: String?
    var tags: [String]
    /// From a scan: the photo was hard to read here. Cleared once the owner
    /// edits the item; never saved.
    var unsure: Bool

    init(id: String = "i_\(UUID().uuidString.prefix(8))", name: String, price: String? = nil,
         description: String? = nil, tags: [String] = [], unsure: Bool = false) {
        self.id = id; self.name = name; self.price = price; self.description = description; self.tags = tags; self.unsure = unsure
    }

    enum CodingKeys: String, CodingKey { case id, name, price, description, tags, unsure }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? "i_\(UUID().uuidString.prefix(8))"
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        price = try? c.decodeIfPresent(String.self, forKey: .price)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        unsure = (try? c.decode(Bool.self, forKey: .unsure)) ?? false
    }
}

// MARK: - Scan drafts (POST /rewards/venues/:id/scan)

/// What a store owner can photograph for the app to fill in
enum VenueScanKind: String {
    case menu, hours, flyer

    var readingMessage: String {
        switch self {
        case .menu: return "Reading your menu\u{2026}"
        case .hours: return "Reading your hours\u{2026}"
        case .flyer: return "Reading your flyer\u{2026}"
        }
    }

    /// Several pages for a menu; one photo for the others
    var maxPhotos: Int { self == .menu ? 4 : 1 }
}

struct MenuScanDraft: Decodable {
    let sections: [StorefrontMenuSection]
    let notes: String?
    let itemCount: Int?
}

struct HoursScanDraft: Decodable {
    struct Day: Decodable, Equatable {
        let day: Int
        let open: String?
        let close: String?
        let isClosed: Bool
        let unsure: Bool?
    }
    let hours: [Day]
    let found: Int
}

struct FlyerScanDraft: Decodable, Equatable {
    struct Event: Decodable, Equatable {
        let localDate: String
        let localTime: String?
        let endTime: String?
        let isFree: Bool?
    }
    let title: String
    let message: String
    let event: Event?
    let expiresOn: String?
    let unsure: [String]
}

struct VenueScanEnvelope<Draft: Decodable>: Decodable {
    let data: VenueScanResponse<Draft>
}

struct VenueScanResponse<Draft: Decodable>: Decodable {
    let kind: String
    let draft: Draft
    let truncated: Bool?
}
