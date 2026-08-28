import Foundation

/// Server-driven partner action catalog rendered on the place detail screen
/// (Delivery / Reserve / Ride chips). Served by GET /api/app/partner-actions;
/// the backend edits the Firestore `partnerActions` collection to add or change
/// partners without an app release.
///
/// Decoding is deliberately lossy at both levels: one malformed group (or
/// provider) is dropped, never the whole catalog — a bad Firestore edit must
/// degrade to "that chip missing", not "row gone".
struct PartnerActionCatalog: Codable {
    let updatedAt: String?
    let groups: [PartnerActionGroup]

    enum CodingKeys: String, CodingKey { case updatedAt, groups }

    init(updatedAt: String?, groups: [PartnerActionGroup]) {
        self.updatedAt = updatedAt
        self.groups = groups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
        var groupsContainer = try container.nestedUnkeyedContainer(forKey: .groups)
        var decoded: [PartnerActionGroup] = []
        while !groupsContainer.isAtEnd {
            if let group = try? groupsContainer.decode(PartnerActionGroup.self) {
                decoded.append(group)
            } else {
                // Skip the malformed element so the container advances
                _ = try? groupsContainer.decode(AnyDecodable.self)
            }
        }
        groups = decoded
    }
}

struct PartnerActionGroup: Codable {
    let id: String
    let title: String
    let icon: String
    let sheetTitle: String
    /// PlaceCategory raw values this group applies to, or ["*"] for all
    let categories: [String]
    /// Optional Google service-option gate (e.g. ["delivery","takeout"]) —
    /// the group hides when the place's flags are ALL known-false; any true
    /// or unknown flag keeps it visible (most places lack the flags until
    /// their Google data is refreshed).
    let venueFlags: [String]?
    let order: Int
    let providers: [PartnerActionProvider]

    enum CodingKeys: String, CodingKey { case id, title, icon, sheetTitle, categories, venueFlags, order, providers }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        icon = (try? container.decode(String.self, forKey: .icon)) ?? "arrow.up.right.square"
        sheetTitle = (try? container.decode(String.self, forKey: .sheetTitle)) ?? title
        categories = (try? container.decode([String].self, forKey: .categories)) ?? ["*"]
        venueFlags = try? container.decodeIfPresent([String].self, forKey: .venueFlags)
        order = (try? container.decode(Int.self, forKey: .order)) ?? 999
        var providersContainer = try container.nestedUnkeyedContainer(forKey: .providers)
        var decoded: [PartnerActionProvider] = []
        while !providersContainer.isAtEnd {
            if let provider = try? providersContainer.decode(PartnerActionProvider.self) {
                decoded.append(provider)
            } else {
                _ = try? providersContainer.decode(AnyDecodable.self)
            }
        }
        providers = decoded
    }
}

struct PartnerActionProvider: Codable {
    let id: String
    let title: String
    /// Required https universal link — app-links into the partner app when
    /// installed. A provider added server-side with only this field works with
    /// zero app changes.
    let webUrlTemplate: String
    /// Optional scheme-first fast path; only used when `appScheme` passes
    /// canOpenURL (which requires the scheme in LSApplicationQueriesSchemes,
    /// so this half is release-gated — web is not).
    let appUrlTemplate: String?
    let appScheme: String?
    /// "inAppBrowser" presents the web URL in an in-app Safari sheet instead
    /// of UIApplication.open — universal-link interception doesn't apply
    /// there, so a partner app that swallows the link and drops the search
    /// context (OpenTable) still lands on the right page. Nil/other = external.
    let openMode: String?
}

/// Consumes-and-discards one element of any shape (lossy array decoding).
private struct AnyDecodable: Decodable {
    init(from decoder: Decoder) throws {
        let container = try? decoder.singleValueContainer()
        if container?.decodeNil() == true { return }
        if (try? container?.decode(Bool.self)) != nil { return }
        if (try? container?.decode(Double.self)) != nil { return }
        if (try? container?.decode(String.self)) != nil { return }
        if (try? decoder.container(keyedBy: DummyKey.self)) != nil { return }
        if (try? decoder.unkeyedContainer()) != nil { return }
    }
    private struct DummyKey: CodingKey {
        var stringValue: String; var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
    }
}
