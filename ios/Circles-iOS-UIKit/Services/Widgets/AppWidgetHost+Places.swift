import UIKit
import SwiftUI
import FavWidgets
import FavWidgetsCore
import StripeApplePay
import PassKit

/// Places for the widgets (NextBar and friends): location, saved places, opening a place page.
extension AppWidgetHost {
    func currentLocation() async -> WidgetCoordinate? {
        await withCheckedContinuation { continuation in
            // Belt and braces: LocationService now fires each completion once,
            // but a continuation resumed twice is a crash, so guard here too.
            let once = OnceFlag()
            LocationService.shared.getCurrentLocation { location in
                guard once.claim() else { return }
                continuation.resume(returning: location.map {
                    WidgetCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                })
            }
            // The mirror-image failure: Core Location never calling back
            // (authorization limbo, a stalled fix) would leave this await
            // hanging and the widget waiting forever. "No location" after
            // 10s is the honest answer instead.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                guard once.claim() else { return }
                continuation.resume(returning: nil)
            }
        }
    }

    /// The user's own saved places plus the network's places around the
    /// query origin (connections and followed people, per the same viewport
    /// endpoint the map and check-in "Nearby" use), filtered by category.
    func fetchPlaces(_ query: WidgetPlaceQuery) async throws -> [WidgetPlaceCandidate] {
        async let mine: [Place] = query.sources.contains(.mine) ? fetchMyPlaces() : []
        async let network: [Place] = (query.near != nil && !query.sources.isDisjoint(with: [.connection, .following]))
            ? fetchNetworkPlaces(near: query.near!, radiusMeters: query.radiusMeters) : []
        let (minePlaces, networkPlaces) = try await (mine, network)

        let connectionIds = Set(NetworkManager.shared.connections
            .filter { $0.relationshipType != "following" }
            .map { $0.connectedUserId })
        let followingIds = Set(NetworkManager.shared.followingUsers.map(\.id))
        let myId = userId
        let wantsCategory: (Place) -> Bool = { query.categories.isEmpty || query.categories.contains($0.category.rawValue) }

        // One entry per venue, remembering everyone who saved it: "You"
        // first, then each connection / followed person by name.
        struct Venue {
            var place: Place
            var source: WidgetPlaceSource
            var savers: [String]
            var coordinate: WidgetCoordinate
        }
        var venues: [String: Venue] = [:]
        var order: [String] = []
        func note(_ place: Place, source: WidgetPlaceSource, saver: String) {
            guard wantsCategory(place), let location = place.location?.clLocation else { return }
            let key = PlaceService.venueKey(place)
            if var venue = venues[key] {
                if !venue.savers.contains(saver) { venue.savers.append(saver) }
                if source == .mine { venue.source = .mine; venue.place = place; venue.savers.removeAll { $0 == "You" }; venue.savers.insert("You", at: 0) }
                venues[key] = venue
            } else {
                venues[key] = Venue(place: place, source: source, savers: [saver],
                                    coordinate: WidgetCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
                order.append(key)
            }
        }

        for place in minePlaces { note(place, source: .mine, saver: "You") }
        for place in networkPlaces {
            if place.addedBy == myId { continue }
            let source: WidgetPlaceSource
            if connectionIds.contains(place.addedBy) { source = .connection }
            else if followingIds.contains(place.addedBy) { source = .following }
            else { source = .connection }   // network endpoint only returns people in the network
            guard query.sources.contains(source) else { continue }
            note(place, source: source, saver: place.addedByUser?.displayName ?? "A connection")
        }

        return order.compactMap { key -> WidgetPlaceCandidate? in
            guard let venue = venues[key] else { return nil }
            let place = venue.place
            let id = place.globalPlaceId ?? place.id
            placeCache[id] = place
            return WidgetPlaceCandidate(
                id: id,
                name: place.name,
                address: place.address,
                coordinate: venue.coordinate,
                category: place.category.rawValue,
                source: venue.source,
                savedByName: venue.savers.first { $0 != "You" },
                savers: venue.savers,
                photoURL: place.photos?.first.flatMap { URL(string: $0) },
                isGlobal: place.globalPlaceId != nil
            )
        }
    }


    func openPlace(_ place: WidgetPlaceRef) {
        guard let presenter = presentingViewController else { return }
        let navigation = presenter.navigationController ?? presenter as? UINavigationController
        if let cached = placeCache[place.id] {
            navigation?.pushViewController(PlaceDetailViewController(place: cached), animated: true)
            return
        }
        let loading = AlertPresenter.showLoading(message: "Loading place...", from: presenter)
        GlobalPlaceService.shared.getGlobalPlace(id: place.id) { result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    switch result {
                    case .success(let response):
                        navigation?.pushViewController(PlaceDetailViewController(place: response.bestDetailPlace()), animated: true)
                    case .failure(let error):
                        AlertPresenter.showError(error, from: presenter)
                    }
                }
            }
        }
    }

    private func fetchMyPlaces() async throws -> [Place] {
        try await withCheckedThrowingContinuation { continuation in
            PlaceService.shared.getMyPlacesForCheckIn { continuation.resume(with: $0) }
        }
    }

    private func fetchNetworkPlaces(near origin: WidgetCoordinate, radiusMeters: Double) async throws -> [Place] {
        try await withCheckedThrowingContinuation { continuation in
            PlaceService.shared.fetchNetworkPlacesInViewport(
                centerLat: origin.latitude, centerLng: origin.longitude, radiusM: radiusMeters, limit: 500
            ) { continuation.resume(with: $0) }
        }
    }

    /// The package's theme built from the app's palette so the tab matches
    /// the rest of FavCircles in light and dark mode.
    static func makeTheme() -> WidgetTheme {
        WidgetTheme(
            primary: Color(uiColor: Constants.Colors.primary),
            accent: Color(uiColor: Constants.Colors.accent),
            background: Color(uiColor: Constants.Colors.background),
            secondaryBackground: Color(uiColor: Constants.Colors.secondaryBackground),
            tertiaryBackground: Color(uiColor: Constants.Colors.tertiaryBackground),
            label: Color(uiColor: Constants.Colors.label),
            secondaryLabel: Color(uiColor: Constants.Colors.secondaryLabel),
            separator: Color(uiColor: Constants.Colors.separator),
            success: Color(uiColor: Constants.Colors.success),
            warning: Color(uiColor: Constants.Colors.warning),
            danger: Color(uiColor: Constants.Colors.danger)
        )
    }
}
