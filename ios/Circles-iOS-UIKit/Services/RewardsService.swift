import Foundation

/// Sticker rewards program: scanning physical venue QR codes, earning points,
/// and redeeming venue-honored offers. Mirrors the ReferralService patterns
/// (singleton, pending-code storage, APIService-backed requests).
class RewardsService {
    static let shared = RewardsService()

    private let apiService = APIService.shared
    private let userDefaults = UserDefaults.standard

    // Sticker code scanned before login/signup, redeemed after auth
    private let kPendingStickerCode = "pending_sticker_code"
    // Share attribution: googlePlaceId -> [refUserId, storedAt]
    private let kShareAttribution = "pending_share_attribution"
    private let shareAttributionTTL: TimeInterval = 48 * 60 * 60

    private init() {}

    // MARK: - Scan (window sticker or register card)

    func scan(code: String, completion: @escaping (Result<RewardScanData, Error>) -> Void) {
        let body: [String: Any] = ["code": code]

        apiService.request(
            endpoint: "rewards/scan",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<RewardScanData>, APIError>) in
            switch result {
            case .success(let response):
                if response.data.awarded != nil {
                    RewardsService.postBalanceChanged()
                }
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Confirm the sticker place was saved (earns save points)

    func confirmStickerSave(code: String, completion: @escaping (Result<RewardSaveData, Error>) -> Void) {
        apiService.request(
            endpoint: "rewards/sticker-save",
            method: .post,
            body: ["code": code],
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<RewardSaveData>, APIError>) in
            switch result {
            case .success(let response):
                if response.data.awarded != nil {
                    RewardsService.postBalanceChanged()
                }
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Lets the home-screen $ badge refresh the moment points are earned or spent
    private static func postBalanceChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .rewardBalanceChanged, object: nil)
        }
    }

    // MARK: - Balance & history

    func getBalance(completion: @escaping (Result<RewardBalanceData, Error>) -> Void) {
        apiService.request(
            endpoint: "rewards/balance",
            method: .get,
            body: nil,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<RewardBalanceData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Redeem an offer (returns a 5-minute voucher)

    func redeemOffer(venueId: String, offerId: String, completion: @escaping (Result<RewardRedeemData, Error>) -> Void) {
        let body: [String: Any] = ["venueId": venueId, "offerId": offerId]

        apiService.request(
            endpoint: "rewards/redeem-offer",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<RewardRedeemData>, APIError>) in
            switch result {
            case .success(let response):
                RewardsService.postBalanceChanged()
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Browse offers (participating venues, saved + nearby)

    func getOffers(lat: Double? = nil, lng: Double? = nil, completion: @escaping (Result<RewardOffersData, Error>) -> Void) {
        var endpoint = "rewards/offers"
        if let lat = lat, let lng = lng {
            endpoint += "?lat=\(lat)&lng=\(lng)"
        }

        apiService.request(
            endpoint: endpoint,
            method: .get,
            body: nil,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<RewardOffersData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Venue owner (self-service offers + earn rate)

    func getMyVenues(completion: @escaping (Result<[AdminVenue], Error>) -> Void) {
        apiService.request(
            endpoint: "rewards/my-venues",
            method: .get,
            body: nil,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<AdminVenueList>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.venues))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func addOffer(venueId: String, title: String, pointsCost: Int, completion: @escaping (Result<[RewardOffer], Error>) -> Void) {
        let body: [String: Any] = ["title": title, "pointsCost": pointsCost]

        apiService.request(
            endpoint: "rewards/venues/\(venueId)/offers",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<VenueOffersData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.offers))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func updateOffer(venueId: String, offerId: String, title: String? = nil, pointsCost: Int? = nil, active: Bool? = nil, completion: @escaping (Result<[RewardOffer], Error>) -> Void) {
        var body: [String: Any] = [:]
        if let title = title { body["title"] = title }
        if let pointsCost = pointsCost { body["pointsCost"] = pointsCost }
        if let active = active { body["active"] = active }

        apiService.request(
            endpoint: "rewards/venues/\(venueId)/offers/\(offerId)",
            method: .put,
            body: body,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<VenueOffersData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.offers))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func updateEarnRate(venueId: String, earnRate: Int, completion: @escaping (Result<Int, Error>) -> Void) {
        apiService.request(
            endpoint: "rewards/venues/\(venueId)",
            method: .patch,
            body: ["earnRate": earnRate],
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<VenueSettingsData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.earnRate))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Replaces the register QR code (old one stops working immediately);
    /// optionally binds a new points-per-purchase value to the fresh code.
    func rotateRegisterCode(venueId: String, earnRate: Int? = nil, completion: @escaping (Result<RotatedRegisterCode, Error>) -> Void) {
        var body: [String: Any] = [:]
        if let earnRate = earnRate { body["earnRate"] = earnRate }

        apiService.request(
            endpoint: "rewards/venues/\(venueId)/register-code",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<RotatedRegisterCode>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Super user (in-app venue management)

    func getRewardsProfile(completion: @escaping (Result<RewardsProfile, Error>) -> Void) {
        apiService.request(
            endpoint: "rewards/me",
            method: .get,
            body: nil,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<RewardsProfile>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func createVenue(_ draft: VenueDraft, completion: @escaping (Result<CreatedVenue, Error>) -> Void) {
        var body: [String: Any] = [
            "venueName": draft.venueName,
            "placeName": draft.venueName,
            "placeAddress": draft.placeAddress,
            "category": draft.category
        ]
        if let contactName = draft.contactName, !contactName.isEmpty {
            body["contactName"] = contactName
        }
        if let contactEmail = draft.contactEmail, !contactEmail.isEmpty {
            body["contactEmail"] = contactEmail
        }
        if let lat = draft.latitude, let lng = draft.longitude {
            body["location"] = ["lat": lat, "lng": lng]
        }
        body["offers"] = draft.offers.map { ["title": $0.title, "pointsCost": $0.pointsCost] }

        apiService.request(
            endpoint: "rewards/venues",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<CreatedVenue>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func listVenues(completion: @escaping (Result<[AdminVenue], Error>) -> Void) {
        apiService.request(
            endpoint: "rewards/venues",
            method: .get,
            body: nil,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<AdminVenueList>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.venues))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func emailVenueQR(venueId: String, completion: @escaping (Result<String, Error>) -> Void) {
        apiService.request(
            endpoint: "rewards/venues/\(venueId)/email-qr",
            method: .post,
            body: nil,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<EmailQRData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.emailedTo))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func setSuperUser(email: String, isSuperUser: Bool, completion: @escaping (Result<String, Error>) -> Void) {
        let body: [String: Any] = ["email": email, "isSuperUser": isSuperUser]

        apiService.request(
            endpoint: "rewards/superusers",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<SetSuperUserData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.message))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Pending sticker code (scanned while logged out)

    func savePendingStickerCode(_ code: String) {
        userDefaults.set(code, forKey: kPendingStickerCode)
    }

    func getPendingStickerCode() -> String? {
        return userDefaults.string(forKey: kPendingStickerCode)
    }

    func clearPendingStickerCode() {
        userDefaults.removeObject(forKey: kPendingStickerCode)
    }

    // MARK: - Share attribution
    // When the user opens a shared place link (circles://place/<id>?ref=<userId>),
    // remember who shared it. If the user then adds that place, the sharer's id
    // rides along on the create request so the backend can credit them.

    func storeShareAttribution(googlePlaceId: String?, refUserId: String) {
        guard let googlePlaceId = googlePlaceId, !googlePlaceId.isEmpty else { return }
        guard refUserId != AuthService.shared.getUserId() else { return }
        var stored = userDefaults.dictionary(forKey: kShareAttribution) as? [String: [String: Any]] ?? [:]
        stored[googlePlaceId] = ["refUserId": refUserId, "storedAt": Date().timeIntervalSince1970]
        userDefaults.set(stored, forKey: kShareAttribution)
    }

    func consumeShareAttribution(forGooglePlaceId googlePlaceId: String?) -> String? {
        guard let googlePlaceId = googlePlaceId,
              var stored = userDefaults.dictionary(forKey: kShareAttribution) as? [String: [String: Any]],
              let entry = stored[googlePlaceId],
              let refUserId = entry["refUserId"] as? String,
              let storedAt = entry["storedAt"] as? TimeInterval else {
            return nil
        }

        stored.removeValue(forKey: googlePlaceId)
        userDefaults.set(stored, forKey: kShareAttribution)

        guard Date().timeIntervalSince1970 - storedAt < shareAttributionTTL else { return nil }
        return refUserId
    }
}

// MARK: - Response Models

struct RewardsEnvelope<T: Codable>: Codable {
    let success: Bool
    let data: T
}

struct RewardScanData: Codable {
    let kind: String // "window" | "register"
    let venue: RewardVenue
    let awarded: RewardAward?
    let alreadySaved: Bool?
    let alreadyEarnedToday: Bool?
    let balance: Int
    let offers: [RewardOffer]?
}

struct RewardVenue: Codable {
    let venueId: String
    let venueName: String
    let placeName: String?
    let placeAddress: String?
    let category: String?
    let googlePlaceId: String?
    let globalPlaceId: String?
    let location: RewardCoordinate?
}

struct RewardCoordinate: Codable {
    let lat: Double
    let lng: Double
}

struct RewardAward: Codable {
    let type: String
    let points: Int
}

struct RewardOffer: Codable {
    let offerId: String
    let title: String
    let pointsCost: Int
    let active: Bool?
}

struct RewardSaveData: Codable {
    let awarded: RewardAward?
    let alreadyAwarded: Bool?
    let balance: Int
}

struct RewardBalanceData: Codable {
    let balance: Int
    let events: [RewardEventItem]
}

struct RewardEventItem: Codable {
    let id: String
    let type: String
    let points: Int
    let venueName: String?
    let offerTitle: String?
    let createdAt: String

    var displayTitle: String {
        switch type {
        case "sticker_signup": return "Joined via sticker\(venueSuffix)"
        case "sticker_save": return "Saved\(venueSuffix)"
        case "venue_visit": return "Purchase\(venueSuffix)"
        case "share_conversion": return "Friend added your shared place"
        case "redemption": return "Redeemed \(offerTitle ?? "offer")\(venueSuffix)"
        default: return type
        }
    }

    private var venueSuffix: String {
        guard let venueName = venueName, !venueName.isEmpty else { return "" }
        return " — \(venueName)"
    }
}

struct RewardVoucher: Codable {
    let voucherCode: String
    let offerTitle: String
    let pointsCost: Int
    let venueName: String
    let expiresAt: String
}

struct RewardRedeemData: Codable {
    let voucher: RewardVoucher
    let balance: Int
}

// MARK: - Browse offers models

struct RewardOffersData: Codable {
    let venues: [OfferVenue]
    let balance: Int
}

struct OfferVenue: Codable {
    let venueId: String
    let venueName: String
    let placeName: String?
    let placeAddress: String?
    let category: String?
    let location: RewardCoordinate?
    let earnRate: Int?
    let savedByUser: Bool?
    let distanceMeters: Double?
    let offers: [RewardOffer]

    var distanceDisplay: String? {
        guard let meters = distanceMeters else { return nil }
        let miles = meters / 1609.34
        if miles < 0.1 { return "nearby" }
        return String(format: "%.1f mi", miles)
    }
}

// MARK: - Super user & venue owner models

struct RewardsProfile: Codable {
    let isSuperUser: Bool
    let ownsVenues: Bool?
    let email: String?
}

struct VenueOffersData: Codable {
    let offers: [RewardOffer]
}

struct VenueSettingsData: Codable {
    let venueId: String
    let earnRate: Int
}

struct RotatedRegisterCode: Codable {
    let venueId: String
    let registerCode: String
    let registerCardUrl: String
    let earnRate: Int
}

struct VenueDraft {
    var venueName: String
    var placeAddress: String
    var category: String
    var contactName: String?
    var contactEmail: String?
    var latitude: Double?
    var longitude: Double?
    var offers: [VenueOfferDraft]
}

struct VenueOfferDraft {
    let title: String
    let pointsCost: Int
}

struct CreatedVenue: Codable {
    let venueId: String
    let venueName: String
    let windowCode: String
    let registerCode: String
    let windowStickerUrl: String
    let registerCardUrl: String
    let emailSent: Bool
    let emailedTo: String?
}

struct AdminVenueList: Codable {
    let venues: [AdminVenue]
    let count: Int
}

struct AdminVenue: Codable {
    let venueId: String
    let venueName: String
    let placeAddress: String?
    let contactEmail: String?
    let windowCode: String
    let registerCode: String
    let active: Bool?
    let stats: AdminVenueStats?
    // Present in /my-venues (and full docs from /venues); optional so older
    // response shapes still decode
    let earnRate: Int?
    let offers: [RewardOffer]?
}

struct AdminVenueStats: Codable {
    let scans: Int?
    let signups: Int?
    let saves: Int?
    let visits: Int?
    let redemptions: Int?
}

struct EmailQRData: Codable {
    let emailedTo: String
}

struct SetSuperUserData: Codable {
    let email: String
    let isSuperUser: Bool
    let message: String
}
