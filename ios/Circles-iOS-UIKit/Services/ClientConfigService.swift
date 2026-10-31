import Foundation

/// The business values the app shows — free-plan limits, store reward
/// defaults, FavCoin amounts, the App Store link — from the server's one
/// source (GET /api/config/client; Wes, 2026-10-31). The last answer is
/// cached; the built-in values are only the offline fallback, so a change on
/// the server reaches every screen on the next launch.
struct ClientConfig: Codable, Equatable {
    struct FreeLimits: Codable, Equatable {
        var maxCircles: Int
        var maxPlacesPerCircle: Int
        var photoPlaces: Int?
        var eventVideoMaxSeconds: Int?
        var eventVideosPerEvent: Int?
    }
    struct StoreRewardDefaults: Codable, Equatable {
        var pointsPerPurchase: Int
        var pointsForSaving: Int
    }
    struct FavCoins: Codable, Equatable {
        var firstPlaceAdded: Double?
        var drinkReceived: Double?
        var eventJoined: Double?
    }

    var version: Int
    var appStoreUrl: String
    var freeLimits: FreeLimits
    var storeRewardDefaults: StoreRewardDefaults
    var favCoins: FavCoins

    /// Offline fallback only — the server is the source.
    static let builtIn = ClientConfig(
        version: 1,
        appStoreUrl: ShareLinks.appStore,
        freeLimits: FreeLimits(maxCircles: 6, maxPlacesPerCircle: 15, photoPlaces: 25,
                               eventVideoMaxSeconds: 15, eventVideosPerEvent: 5),
        storeRewardDefaults: StoreRewardDefaults(pointsPerPurchase: 25, pointsForSaving: 25),
        favCoins: FavCoins(firstPlaceAdded: 25, drinkReceived: 1, eventJoined: 1))
}

final class ClientConfigService {
    static let shared = ClientConfigService()

    private static let cacheKey = "clientConfig.v1"
    private let lock = NSLock()
    private var current: ClientConfig
    private var lastFetch: Date?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(ClientConfig.self, from: data) {
            current = cached
        } else {
            current = .builtIn
        }
    }

    var config: ClientConfig {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// Fetch at most every 30 minutes (launch and coming back to the app).
    /// A failed fetch keeps what we have — never blanks a value.
    func refreshIfStale() {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 30 * 60 { return }
        lastFetch = Date()
        APIService.shared.request(endpoint: "config/client", method: .get, requiresAuth: false) { [weak self] (result: Result<Envelope, APIError>) in
            guard let self, case .success(let envelope) = result else { return }
            self.lock.lock()
            self.current = envelope.data
            self.lock.unlock()
            if let data = try? JSONEncoder().encode(envelope.data) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
        }
    }

    private struct Envelope: Decodable {
        let success: Bool
        let data: ClientConfig
    }
}
