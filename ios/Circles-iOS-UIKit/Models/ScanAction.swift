import Foundation

/// What a Scan Action QR does, as the server tells it
/// (GET /api/scan-actions/:code). The places are venue cards only: name,
/// address, spot, a public photo; never anyone's notes.
struct ScanAction: Decodable, Equatable {
    enum Kind: String, Decodable, Equatable {
        case place, placeSet, guide, storeSetup
        /// A kind a newer server knows and this build doesn't
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    struct Creator: Decodable, Equatable {
        let id: String
        let displayName: String
        let profilePicture: String?
    }

    struct Guide: Decodable, Equatable {
        let id: String
        let appGuide: String
        let title: String
        let blurb: String?
    }

    struct Store: Decodable, Equatable {
        let venueId: String?
        let globalPlaceId: String?
        let googlePlaceId: String?
        let name: String?
        let address: String?
        let redeemed: Bool?
        let redeemedByViewer: Bool?
    }

    struct Spot: Decodable, Equatable {
        let lat: Double
        let lng: Double
    }

    struct Place: Decodable, Equatable {
        let globalPlaceId: String
        let name: String
        let address: String?
        let category: String?
        let photoUrl: String?
        let location: Spot?
        let googlePlaceId: String?
        let applePlaceId: String?
        let alreadySaved: Bool?
        let savedPlaceId: String?
        let savedCircleId: String?
    }

    let code: String
    let kind: Kind
    let url: String?
    let title: String?
    let note: String?
    let expired: Bool
    let creator: Creator?
    let guide: Guide?
    let store: Store?
    let places: [Place]

    enum CodingKeys: String, CodingKey {
        case code, kind, url, title, note, expired, creator, guide, store, places
    }

    init(code: String, kind: Kind, url: String? = nil, title: String? = nil, note: String? = nil, expired: Bool = false,
         creator: Creator? = nil, guide: Guide? = nil, store: Store? = nil, places: [Place] = []) {
        self.code = code; self.kind = kind; self.url = url; self.title = title; self.note = note
        self.expired = expired; self.creator = creator; self.guide = guide; self.store = store; self.places = places
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .unknown
        url = try c.decodeIfPresent(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        expired = (try c.decodeIfPresent(Bool.self, forKey: .expired)) ?? false
        creator = try c.decodeIfPresent(Creator.self, forKey: .creator)
        guide = try c.decodeIfPresent(Guide.self, forKey: .guide)
        store = try c.decodeIfPresent(Store.self, forKey: .store)
        places = (try c.decodeIfPresent([Place].self, forKey: .places)) ?? []
    }
}

/// A QR just made (POST /api/scan-actions)
struct ScanActionCreated: Decodable, Equatable {
    let code: String
    let url: String
    let kind: String
    let title: String?
    let expiresAt: String?
    let leftOutPrivate: Int?
    let leftOutHidden: Int?
    let places: [ScanAction.Place]?
}

/// What finishing a place / set QR did (POST /api/scan-actions/:code/complete)
struct ScanActionSaveResult: Decodable, Equatable {
    struct Saved: Decodable, Equatable {
        let globalPlaceId: String
        let name: String?
        let placeId: String?
        let circleId: String?
        let circleName: String?
        let message: String?
        let upgradeRequired: Bool?
    }
    let circleId: String?
    let saved: [Saved]
    let alreadySaved: [Saved]
    let failed: [Saved]
}

/// What redeeming a store setup QR did
struct ScanActionStoreResult: Decodable, Equatable {
    let venueId: String?
    let alreadyRedeemed: Bool?
}
