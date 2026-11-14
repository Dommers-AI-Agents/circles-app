import Foundation

/// A store's automatic nudges (2026-11-09; server: services/storeAutomations.js):
/// win-back, birthday and almost-there, each a switch with its own bonus.
struct StoreAutomations: Codable, Equatable {
    struct WinBack: Codable, Equatable {
        var enabled: Bool
        /// Days without a purchase before the nudge: 14, 30, 60 or 90
        var days: Int
        var bonusPoints: Int
        /// One of the store's coupons, claimed for the customer with the nudge (2026-11-14)
        var couponId: String? = nil
    }
    struct Birthday: Codable, Equatable {
        var enabled: Bool
        var bonusPoints: Int
    }
    struct AlmostThere: Codable, Equatable {
        var enabled: Bool
    }
    var winBack: WinBack
    var birthday: Birthday
    var almostThere: AlmostThere

    static let off = StoreAutomations(winBack: .init(enabled: false, days: 30, bonusPoints: 0),
                                      birthday: .init(enabled: false, bonusPoints: 0),
                                      almostThere: .init(enabled: false))

    var asBody: [String: Any] {
        [
            "winBack": ["enabled": winBack.enabled, "days": winBack.days, "bonusPoints": winBack.bonusPoints, "couponId": winBack.couponId ?? NSNull()],
            "birthday": ["enabled": birthday.enabled, "bonusPoints": birthday.bonusPoints],
            "almostThere": ["enabled": almostThere.enabled]
        ]
    }
}

/// Per automation: sent so far, and how many of those bought again since
struct StoreAutomationStat: Codable, Equatable {
    let sent: Int
    let cameBack: Int
}

struct StoreAutomationStats: Codable, Equatable {
    let winBack: StoreAutomationStat
    let birthday: StoreAutomationStat
    let almostThere: StoreAutomationStat
}

struct StoreAutomationsData: Codable {
    let settings: StoreAutomations
    let stats: StoreAutomationStats?
}

private struct StoreAutomationsSaved: Codable { let settings: StoreAutomations }
private struct BirthdayData: Codable { let birthday: String? }

extension RewardsService {

    func fetchAutomations(venueId: String, completion: @escaping (Result<StoreAutomationsData, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/automations", method: .get, requiresAuth: true) {
            (result: Result<RewardsEnvelope<StoreAutomationsData>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }

    /// The whole settings object is sent each time
    func updateAutomations(venueId: String, settings: StoreAutomations, completion: @escaping (Result<StoreAutomations, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/automations", method: .put, body: settings.asBody, requiresAuth: true) {
            (result: Result<RewardsEnvelope<StoreAutomationsSaved>, APIError>) in
            completion(result.map(\.data.settings).mapError { $0 as Error })
        }
    }

    // MARK: Birthday (the customer's; month and day only)

    func fetchBirthday(completion: @escaping (Result<String?, Error>) -> Void) {
        APIService.shared.request(endpoint: "users/me/birthday", method: .get, requiresAuth: true) {
            (result: Result<RewardsEnvelope<BirthdayData>, APIError>) in
            completion(result.map(\.data.birthday).mapError { $0 as Error })
        }
    }

    /// "MM-DD", or nil to clear it
    func setBirthday(_ birthday: String?, completion: @escaping (Result<String?, Error>) -> Void) {
        APIService.shared.request(endpoint: "users/me/birthday", method: .put, body: ["birthday": birthday ?? NSNull()], requiresAuth: true) {
            (result: Result<RewardsEnvelope<BirthdayData>, APIError>) in
            completion(result.map(\.data.birthday).mapError { $0 as Error })
        }
    }
}
