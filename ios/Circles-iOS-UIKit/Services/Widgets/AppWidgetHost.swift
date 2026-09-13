import UIKit
import SwiftUI
import FavWidgets
import FavWidgetsCore

/// The app's side of the FavWidgets host contract: data sync, analytics,
/// haptics, sharing, alerts, connections, and postcard delivery. One per
/// signed-in user; the Widgets tab owns it.
final class AppWidgetHost: FavWidgetHost {
    /// The Widgets tab; sheets and alerts present from whatever is on
    /// screen above it (a pushed full view, the Manage sheet), resolved at
    /// call time — the tab itself leaves the window while a page is pushed.
    weak var presenter: UIViewController?

    private var presentingViewController: UIViewController? {
        guard let presenter else { return nil }
        var top = presenter.navigationController?.visibleViewController ?? presenter
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    let dataStore: WidgetDataStore
    let userId: String

    init(userId: String) {
        self.userId = userId
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let directory = caches.appendingPathComponent("HomeWidgets", isDirectory: true).appendingPathComponent(userId, isDirectory: true)
        dataStore = CachedWidgetDataStore(wrapping: HomeWidgetsAPIDataStore(), directory: directory)
    }

    var currentUserId: String? { userId }

    func track(_ event: WidgetAnalyticsEvent) {
        AnalyticsService.shared.logEvent(event.name, parameters: event.parameters)
    }

    func haptic(_ kind: WidgetHaptic) {
        switch kind {
        case .light: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    func openURL(_ url: URL) {
        UIApplication.shared.open(url)
    }

    func share(_ items: [WidgetShareItem]) {
        let activityItems: [Any] = items.compactMap { item in
            switch item {
            case .text(let text): return text
            case .url(let url): return url
            case .imageJPEG(let data): return UIImage(data: data)
            }
        }
        guard let presenter = presentingViewController, !activityItems.isEmpty else { return }
        let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = presenter.view
        presenter.present(activityVC, animated: true)
    }

    func presentAlert(_ alert: WidgetAlert) {
        guard let presenter = presentingViewController else { return }
        AlertPresenter.showInfo(title: alert.title, message: alert.message, from: presenter)
    }

    func fetchConnections() async throws -> [WidgetContact] {
        let users: [User] = try await withCheckedThrowingContinuation { continuation in
            UserService.shared.getFriends { result in
                continuation.resume(with: result)
            }
        }
        return users.map { user in
            WidgetContact(id: user.id, displayName: user.displayName,
                          avatarURL: user.profilePicture.flatMap { URL(string: $0) })
        }
    }

    func sendPostcard(_ postcard: WidgetPostcardSend) async throws -> WidgetPostcardReceipt {
        try await HomeWidgetsPostcardSender.send(postcard)
    }

    /// Not wired in v1; the hook exists so bill split / postcard can pick up
    /// the current venue once visit detection exposes it.
    func nearbyOrCurrentPlace() async -> WidgetPlaceRef? { nil }

    // MARK: - Places (NextBar)

    /// Places handed to widgets, kept so `openPlace` can push the real
    /// detail page without a refetch.
    private var placeCache: [String: Place] = [:]

    func currentLocation() async -> WidgetCoordinate? {
        await withCheckedContinuation { continuation in
            LocationService.shared.getCurrentLocation { location in
                continuation.resume(returning: location.map {
                    WidgetCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                })
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

        var candidates: [WidgetPlaceCandidate] = []
        var seenVenues = Set<String>()
        func append(_ place: Place, source: WidgetPlaceSource) {
            guard wantsCategory(place), let location = place.location?.clLocation else { return }
            let key = PlaceService.venueKey(place)
            guard !seenVenues.contains(key) else { return }
            seenVenues.insert(key)
            let id = place.globalPlaceId ?? place.id
            placeCache[id] = place
            candidates.append(WidgetPlaceCandidate(
                id: id,
                name: place.name,
                address: place.address,
                coordinate: WidgetCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                category: place.category.rawValue,
                source: source,
                savedByName: source == .mine ? nil : place.addedByUser?.displayName,
                photoURL: place.photos?.first.flatMap { URL(string: $0) },
                isGlobal: place.globalPlaceId != nil
            ))
        }

        for place in minePlaces { append(place, source: .mine) }
        for place in networkPlaces {
            if place.addedBy == myId { continue }
            let source: WidgetPlaceSource
            if connectionIds.contains(place.addedBy) { source = .connection }
            else if followingIds.contains(place.addedBy) { source = .following }
            else { source = .connection }   // network endpoint only returns people in the network
            guard query.sources.contains(source) else { continue }
            append(place, source: source)
        }
        return candidates
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
