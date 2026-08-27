import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Puts the user's saved places into iOS system search (Spotlight), so "what
/// was that place called?" gets answered from the home screen without opening
/// the app. Index identity is `place:<saveDocId>`; tapping a result routes
/// through SceneDelegate's CSSearchableItemActionType branch into the normal
/// place-detail deep link.
///
/// The index is rebuilt from `places/my-places` once per session (post-launch
/// side effect) — deletions and edits made on other devices heal on the next
/// open. Saves and deletes made on THIS device update the index immediately.
final class SpotlightIndexService {

    static let shared = SpotlightIndexService()
    private init() {}

    static let domain = "savedPlaces"
    static let identifierPrefix = "place:"

    private var hasRefreshedThisSession = false

    /// Extracts the place id from a Spotlight result's uniqueIdentifier.
    static func placeId(fromSpotlightIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        return String(identifier.dropFirst(identifierPrefix.count))
    }

    /// Full rebuild, throttled to once per session. Fire-and-forget: Spotlight
    /// is a convenience mirror, so failures only log.
    func refreshIndexIfNeeded() {
        guard !hasRefreshedThisSession, AuthService.shared.isLoggedIn else { return }
        hasRefreshedThisSession = true

        PlaceService.shared.getMyPlacesForCheckIn { [weak self] result in
            guard case .success(let places) = result else { return }
            self?.rebuildIndex(with: places)
        }
    }

    /// Wipe-and-replace within our domain, so stale rows (deleted elsewhere,
    /// renamed venues) can't linger.
    private func rebuildIndex(with places: [Place]) {
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [Self.domain]) { _ in
            let items = places.map(Self.searchableItem)
            index.indexSearchableItems(items) { error in
                if let error = error {
                    Logger.warning("Spotlight rebuild failed: \(error.localizedDescription)")
                } else {
                    Logger.debug("Spotlight indexed \(items.count) saved places")
                }
            }
        }
    }

    /// Index one place immediately (called on save so a just-added place is
    /// findable right away).
    func indexPlace(_ place: Place) {
        CSSearchableIndex.default().indexSearchableItems([Self.searchableItem(for: place)]) { error in
            if let error = error {
                Logger.warning("Spotlight index of \(place.id) failed: \(error.localizedDescription)")
            }
        }
    }

    func removePlace(id: String) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: [Self.identifierPrefix + id]) { _ in }
    }

    /// Saved places are personal data — clear them from system search when the
    /// account signs out.
    func clearIndex() {
        hasRefreshedThisSession = false
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [Self.domain]) { _ in }
    }

    private static func searchableItem(for place: Place) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.item)
        attributes.title = place.name
        var descriptionParts = [place.address]
        let category = place.category.displayName
        if !category.isEmpty { descriptionParts.append(category) }
        attributes.contentDescription = descriptionParts.joined(separator: " · ")
        var keywords = [category, "FavCircles"]
        if let city = place.city { keywords.append(city) }
        if let tags = place.tags { keywords.append(contentsOf: tags) }
        attributes.keywords = keywords.filter { !$0.isEmpty }
        if let location = place.location, location.coordinates.count == 2 {
            // GeoJSON order: [lng, lat]
            attributes.longitude = NSNumber(value: location.coordinates[0])
            attributes.latitude = NSNumber(value: location.coordinates[1])
        }

        let item = CSSearchableItem(
            uniqueIdentifier: identifierPrefix + place.id,
            domainIdentifier: domain,
            attributeSet: attributes
        )
        // We rebuild each session; a long expiry keeps places findable for
        // users who open the app rarely (exactly who Spotlight recall serves).
        item.expirationDate = .distantFuture
        return item
    }
}
