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
                self.storeActiveVoucher(response.data.voucher)
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Active voucher
    // The voucher outlives the voucher screen: users can dismiss it, use the
    // app, and reopen it from the Rewards page until the expiry passes.

    private var kActiveVoucher: String { "active_reward_voucher" }

    func storeActiveVoucher(_ voucher: RewardVoucher) {
        if let data = try? JSONEncoder().encode(voucher) {
            userDefaults.set(data, forKey: kActiveVoucher)
        }
    }

    /// Returns the stored voucher if it hasn't expired; clears it otherwise.
    func getActiveVoucher() -> RewardVoucher? {
        guard let data = userDefaults.data(forKey: kActiveVoucher),
              let voucher = try? JSONDecoder().decode(RewardVoucher.self, from: data) else {
            return nil
        }
        guard let expiry = voucher.expiryDate, expiry > Date() else {
            clearActiveVoucher()
            return nil
        }
        return voucher
    }

    func clearActiveVoucher() {
        userDefaults.removeObject(forKey: kActiveVoucher)
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

    // MARK: - Place-page rewards (venue offers + announcements on a place)

    /// Rewards data for a place's detail page. `data.venue == nil` means the
    /// place has no enrolled venue — the common case, not an error.
    func getVenueByPlace(placeId: String, googlePlaceId: String? = nil, completion: @escaping (Result<PlaceVenueData, Error>) -> Void) {
        let encodedId = placeId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? placeId
        var endpoint = "rewards/venues/by-place/\(encodedId)"
        if let googlePlaceId = googlePlaceId,
           let encoded = googlePlaceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            endpoint += "?googlePlaceId=\(encoded)"
        }

        apiService.request(
            endpoint: endpoint,
            method: .get,
            body: nil,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<PlaceVenueData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Claim a business from its place page. Works whether or not the place
    /// is enrolled in the sticker program — the contact info is emailed to
    /// the admin, who verifies and approves.
    func claimPlace(placeId: String, googlePlaceId: String? = nil, contactName: String? = nil, contactEmail: String? = nil, contactPhone: String? = nil, message: String? = nil, completion: @escaping (Result<VenueClaim, Error>) -> Void) {
        var body: [String: Any] = [:]
        if let googlePlaceId = googlePlaceId { body["googlePlaceId"] = googlePlaceId }
        if let contactName = contactName, !contactName.isEmpty { body["contactName"] = contactName }
        if let contactEmail = contactEmail, !contactEmail.isEmpty { body["contactEmail"] = contactEmail }
        if let contactPhone = contactPhone, !contactPhone.isEmpty { body["contactPhone"] = contactPhone }
        if let message = message, !message.isEmpty { body["message"] = message }

        apiService.request(
            endpoint: "rewards/places/\(placeId)/claim",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<ClaimResponseData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.claim))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Venue owner announcements

    func addAnnouncement(venueId: String, title: String, message: String, expiresAt: String? = nil, completion: @escaping (Result<[VenueAnnouncement], Error>) -> Void) {
        var body: [String: Any] = ["title": title, "message": message]
        if let expiresAt = expiresAt { body["expiresAt"] = expiresAt }

        apiService.request(
            endpoint: "rewards/venues/\(venueId)/announcements",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<VenueAnnouncementsData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.announcements))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Pass `clearExpiry: true` to remove an expiry date (sends an explicit null)
    func updateAnnouncement(venueId: String, announcementId: String, title: String? = nil, message: String? = nil, expiresAt: String? = nil, clearExpiry: Bool = false, completion: @escaping (Result<[VenueAnnouncement], Error>) -> Void) {
        var body: [String: Any] = [:]
        if let title = title { body["title"] = title }
        if let message = message { body["message"] = message }
        if clearExpiry {
            body["expiresAt"] = NSNull()
        } else if let expiresAt = expiresAt {
            body["expiresAt"] = expiresAt
        }

        apiService.request(
            endpoint: "rewards/venues/\(venueId)/announcements/\(announcementId)",
            method: .put,
            body: body,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<VenueAnnouncementsData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.announcements))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func deleteAnnouncement(venueId: String, announcementId: String, completion: @escaping (Result<[VenueAnnouncement], Error>) -> Void) {
        apiService.request(
            endpoint: "rewards/venues/\(venueId)/announcements/\(announcementId)",
            method: .delete,
            body: nil,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<VenueAnnouncementsData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.announcements))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Ownership claims (super-user review)

    func listClaims(status: String = "pending", completion: @escaping (Result<[VenueClaim], Error>) -> Void) {
        apiService.request(
            endpoint: "rewards/claims?status=\(status)",
            method: .get,
            body: nil,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<VenueClaimList>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.claims))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func approveClaim(claimId: String, completion: @escaping (Result<VenueClaim, Error>) -> Void) {
        apiService.request(
            endpoint: "rewards/claims/\(claimId)/approve",
            method: .post,
            body: nil,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<ClaimResponseData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.claim))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func denyClaim(claimId: String, reason: String? = nil, completion: @escaping (Result<VenueClaim, Error>) -> Void) {
        var body: [String: Any] = [:]
        if let reason = reason, !reason.isEmpty { body["reason"] = reason }

        apiService.request(
            endpoint: "rewards/claims/\(claimId)/deny",
            method: .post,
            body: body,
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<ClaimResponseData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.claim))
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

    /// Super-user: link a venue to its owner's account by email
    func assignVenueOwner(venueId: String, email: String, completion: @escaping (Result<String, Error>) -> Void) {
        apiService.request(
            endpoint: "rewards/venues/\(venueId)/owner",
            method: .post,
            body: ["email": email],
            requiresAuth: true
        ) { (result: Result<RewardsEnvelope<VenueOwnerData>, APIError>) in
            switch result {
            case .success(let response):
                completion(.success(response.data.ownerEmail))
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

    var expiryDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiresAt)
    }
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
    let googlePlaceId: String?
    let globalPlaceId: String?
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

// MARK: - Place-page venue models (offers + announcements shown on a place)

/// Rewards data for one place's page. `venue == nil` means the place has no
/// enrolled venue — the whole rewards section should be hidden.
struct PlaceVenueData: Codable {
    let venue: PlaceVenue?
    let offers: [RewardOffer]?
    let announcements: [VenueAnnouncement]?
    let balance: Int?
    let isOwner: Bool?
    let claim: PlaceVenueClaim?
}

struct PlaceVenue: Codable {
    let venueId: String
    let venueName: String
    let placeName: String?
    let placeAddress: String?
    let category: String?
    let googlePlaceId: String?
    let globalPlaceId: String?
    let location: RewardCoordinate?
    let earnRate: Int?
}

struct PlaceVenueClaim: Codable {
    let canClaim: Bool
    let myClaimStatus: String? // "pending" | "approved" | "denied" | nil
}

struct VenueAnnouncement: Codable {
    let announcementId: String
    let title: String
    let message: String
    let expiresAt: String?
    let createdAt: String?

    var expiryDate: Date? {
        guard let expiresAt = expiresAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiresAt)
    }

    var isExpired: Bool {
        guard let expiry = expiryDate else { return false }
        return expiry <= Date()
    }
}

struct VenueAnnouncementsData: Codable {
    let announcements: [VenueAnnouncement]
}

// MARK: - Ownership claim models

struct VenueClaim: Codable {
    let claimId: String
    let venueId: String?   // nil for claims on places not yet in the sticker program
    let venueName: String?
    let userId: String
    let userEmail: String?
    let userDisplayName: String?
    let message: String?
    // Contact info the claimer entered — the admin's verification channel
    let contactName: String?
    let contactEmail: String?
    let contactPhone: String?
    let placeName: String?
    let placeAddress: String?
    let status: String
    let denialReason: String?
    let createdAt: String?
}

struct VenueClaimList: Codable {
    let claims: [VenueClaim]
    let count: Int
}

struct ClaimResponseData: Codable {
    let claim: VenueClaim
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

struct VenueOwnerData: Codable {
    let venueId: String
    let ownerEmail: String
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
    let announcements: [VenueAnnouncement]?
    // Place identity, for jumping from the manage hub to the public place page
    let googlePlaceId: String?
    let globalPlaceId: String?
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
