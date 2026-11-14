import Foundation

/// A store's Insights (2026-11-09; server: services/venueInsights.js).
/// Business only; cached an hour on the server (`stale` true while it refreshes).
struct VenueInsightsData: Codable, Equatable {
    struct Customers: Codable, Equatable {
        let visits: Int
        let visitors: Int
        let newCustomers: Int
        let returningCustomers: Int
        /// Everyone who ever bought here and is still in the program
        let total: Int
        let repeatRatePct: Int?
        let regulars: Int
        let lapsed: Int
        /// New customers whose first purchase paid a friend's invite (2026-11-09)
        var referred: Int? = nil
    }
    struct Busiest: Codable, Equatable {
        let hours: [Int]
        let days: [Int]
    }
    struct Offer: Codable, Equatable {
        let offerId: String?
        let title: String
        let redemptions: Int
    }
    struct Score: Codable, Equatable {
        struct Recent: Codable, Equatable {
            let rating: Int
            let at: String?
        }
        struct Google: Codable, Equatable {
            let rating: Double
            let total: Int
        }
        let average: Double?
        let ratings: Int
        let recommend: Int
        let recommendPct: Int?
        let trend: Double?
        let recent: [Recent]
        let google: Google?
    }
    struct Comments: Codable, Equatable {
        struct Awaiting: Codable, Equatable {
            let id: String
            let createdAt: String?
            let text: String?
            let userId: String?
        }
        let total: Int
        let inPeriod: Int
        let awaitingReply: Int
        let awaiting: [Awaiting]
    }

    let range: String
    let since: String?
    let computedAt: String?
    let customers: Customers
    let busiest: Busiest
    let redemptions: Int
    let offers: [Offer]
    let score: Score
    let comments: Comments
    let saves: Int
    let followers: Int
    let stale: Bool?
    /// Flyer coupons (2026-11-14): per coupon, scans → claims → used, new
    /// customers, and who came in after claiming. nil from a cache made before.
    var campaigns: [Campaign]? = nil
    /// Posts (2026-11-14): what each offer, announcement or event reached, and
    /// how many customers came in after it went. nil from an older cache.
    var posts: [Post]? = nil

    struct Post: Codable, Equatable {
        let id: String?
        let kind: String
        let title: String
        let at: String?
        let sentTo: Int
        let audience: Int?
        let cameIn: Int
    }

    struct Campaign: Codable, Equatable {
        let couponId: String
        let title: String
        let campaign: String?
        let expiresAt: String?
        let state: String?
        let scans: Int
        let claims: Int
        let used: Int
        let newCustomers: Int
        let cameIn: Int
    }
}

extension RewardsService {
    /// `range` is one of VenueInsightsCopy.Range's raw values: 30d, 90d, 12m
    func getVenueInsights(venueId: String, range: String, completion: @escaping (Result<VenueInsightsData, Error>) -> Void) {
        APIService.shared.request(endpoint: "rewards/venues/\(venueId)/insights?range=\(range)", method: .get, requiresAuth: true) {
            (result: Result<RewardsEnvelope<VenueInsightsData>, APIError>) in
            completion(result.map(\.data).mapError { $0 as Error })
        }
    }
}
