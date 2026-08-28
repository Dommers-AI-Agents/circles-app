import Foundation
import UIKit

/// Partner action deep links on the place detail screen (Delivery / Reserve /
/// Ride). The catalog is server-driven (GET app/partner-actions, backed by the
/// Firestore `partnerActions` collection) so partners and affiliate URL swaps
/// need no app release. Mirrors RewardsService (singleton, APIService-backed)
/// and UpdateService (UserDefaults-cached, throttled fetch).
///
/// Fails closed at every layer: fetch failure → last-good persisted catalog →
/// empty (row stays collapsed). Never blocks or errors the place screen.
class PartnerActionsService {
    static let shared = PartnerActionsService()

    private let apiService = APIService.shared
    private let userDefaults = UserDefaults.standard

    private let kCatalogCache = "partner_actions_catalog_v2"
    private let kCatalogCachedAt = "partner_actions_catalog_cached_at_v2"
    private let cacheTTL: TimeInterval = 6 * 60 * 60

    private var sessionCatalog: PartnerActionCatalog?

    private init() {}

    // MARK: - Catalog

    func getCatalog(completion: @escaping (PartnerActionCatalog) -> Void) {
        if let cached = sessionCatalog {
            completion(cached)
            return
        }
        if let persisted = persistedCatalog(), !isPersistedStale() {
            sessionCatalog = persisted
            completion(persisted)
            return
        }

        apiService.request(
            endpoint: "app/partner-actions",
            method: .get,
            body: nil,
            requiresAuth: true
        ) { [weak self] (result: Result<RewardsEnvelope<PartnerActionCatalog>, APIError>) in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                self.sessionCatalog = response.data
                self.persist(response.data)
                completion(response.data)
            case .failure:
                // Stale beats empty; empty beats broken
                let fallback = self.persistedCatalog() ?? PartnerActionCatalog(updatedAt: nil, groups: [])
                self.sessionCatalog = fallback
                completion(fallback)
            }
        }
    }

    private func persist(_ catalog: PartnerActionCatalog) {
        if let data = try? JSONEncoder().encode(catalog) {
            userDefaults.set(data, forKey: kCatalogCache)
            userDefaults.set(Date().timeIntervalSince1970, forKey: kCatalogCachedAt)
        }
    }

    private func persistedCatalog() -> PartnerActionCatalog? {
        guard let data = userDefaults.data(forKey: kCatalogCache) else { return nil }
        return try? JSONDecoder().decode(PartnerActionCatalog.self, from: data)
    }

    private func isPersistedStale() -> Bool {
        let cachedAt = userDefaults.double(forKey: kCatalogCachedAt)
        return Date().timeIntervalSince1970 - cachedAt > cacheTTL
    }

    // MARK: - Eligibility

    /// Groups applicable to this place, with every provider's URL pre-validated.
    /// Providers whose templates reference data the place doesn't have are
    /// dropped; groups with no surviving providers are dropped; capped at 3
    /// (the chip row's proven untruncated geometry).
    func eligibleGroups(for place: Place, from catalog: PartnerActionCatalog) -> [PartnerActionGroup] {
        // Home and work are personal pins, never commerce — wildcard-proof
        guard place.category != .home, place.category != .work else { return [] }

        let category = place.category.rawValue
        let eligible = catalog.groups.filter { group in
            group.categories.contains("*") || group.categories.contains(category)
        }.filter { group in
            venueFlagsAllow(group, for: place)
        }.filter { group in
            group.providers.contains { renderedURL(template: $0.webUrlTemplate, place: place) != nil }
        }
        return Array(eligible.sorted { $0.order < $1.order }.prefix(3))
    }

    /// Google service-option gate: hide the group only when EVERY listed flag
    /// is known-false for this place ("definitively doesn't deliver"). Any
    /// true flag, or any unknown (nil) flag, keeps the group visible — most
    /// places won't carry the flags until their Google data refreshes, and
    /// the chip must not vanish on missing data.
    private func venueFlagsAllow(_ group: PartnerActionGroup, for place: Place) -> Bool {
        guard let flags = group.venueFlags, !flags.isEmpty else { return true }
        let values = flags.map { venueFlagValue($0, on: place) }
        return !values.allSatisfy { $0 == false }
    }

    private func venueFlagValue(_ flag: String, on place: Place) -> Bool? {
        switch flag {
        case "delivery": return place.delivery
        case "dineIn": return place.dineIn
        case "reservable": return place.reservable
        case "takeout": return place.takeout
        case "curbsidePickup": return place.curbsidePickup
        default: return nil   // unknown flag name from a future catalog → no-op
        }
    }

    /// Providers within a group whose web URL renders for this place.
    func usableProviders(in group: PartnerActionGroup, for place: Place) -> [PartnerActionProvider] {
        group.providers.filter { renderedURL(template: $0.webUrlTemplate, place: place) != nil }
    }

    // MARK: - Template rendering

    /// Substitutes {name} {address} {city} {lat} {lng} {googlePlaceId} into a
    /// template. Returns nil when the template references a variable the place
    /// can't supply (except {city}, which degrades to empty). Values are
    /// encoded with a strict alphanumeric set — .urlQueryAllowed leaves & and +
    /// raw, which corrupts names like "P&J Cafe" inside query values.
    func renderedURL(template: String, place: Place) -> URL? {
        var rendered = template

        func substitute(_ variable: String, _ value: String?, required: Bool) -> Bool {
            let token = "{\(variable)}"
            guard rendered.contains(token) else { return true }
            guard let value = value, !value.isEmpty else {
                if required { return false }
                rendered = rendered.replacingOccurrences(of: token, with: "")
                return true
            }
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            rendered = rendered.replacingOccurrences(of: token, with: encoded)
            return true
        }

        let coordinate = place.location?.clLocation?.coordinate
        guard substitute("name", place.name, required: true),
              substitute("address", place.address, required: true),
              substitute("city", place.city, required: false),
              substitute("lat", coordinate.map { String($0.latitude) }, required: true),
              substitute("lng", coordinate.map { String($0.longitude) }, required: true),
              substitute("googlePlaceId", place.googlePlaceId, required: true)
        else { return nil }

        return URL(string: rendered)
    }

    // MARK: - Opening

    /// Scheme-first when the partner app is installed (and its scheme is
    /// whitelisted in LSApplicationQueriesSchemes), else the web universal
    /// link — which itself app-links into the partner app when installed.
    func open(provider: PartnerActionProvider, group: PartnerActionGroup, place: Place) {
        var target: URL?
        if let scheme = provider.appScheme,
           let probe = URL(string: "\(scheme)://"),
           UIApplication.shared.canOpenURL(probe),
           let appTemplate = provider.appUrlTemplate,
           let appURL = renderedURL(template: appTemplate, place: place) {
            target = appURL
        } else {
            target = renderedURL(template: provider.webUrlTemplate, place: place)
        }
        guard let url = target else { return }
        UIApplication.shared.open(url)
        AnalyticsService.shared.logEvent("partner_action_tapped", parameters: [
            "group": group.id,
            "provider": provider.id,
            "category": place.category.rawValue
        ])
    }
}
