import UIKit
import SwiftUI
import FavWidgets
import FavWidgetsCore
import StripeApplePay
import PassKit

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

    /// Accepted connections (the `connections` collection — not the legacy
    /// `users/me/friends` array, which is empty for most accounts).
    func fetchConnections() async throws -> [WidgetContact] {
        let users: [User] = try await withCheckedThrowingContinuation { continuation in
            NetworkManager.shared.getConnections { result in
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

    // MARK: - Media

    /// Same pipeline as place/profile photos (compresses, returns a public URL).
    func uploadImage(_ jpeg: Data) async throws -> URL {
        let urlString: String = try await withCheckedThrowingContinuation { continuation in
            PlaceService.shared.uploadImage(jpeg) { continuation.resume(with: $0) }
        }
        guard let url = URL(string: urlString) else { throw WidgetAPIError(status: 500, message: "Bad upload URL") }
        return url
    }

    /// Print artwork goes to its own endpoint, never through `uploadImage`.
    /// That path targets 750KB and downsizes to 1280px on its second attempt,
    /// which would quietly turn a 300 DPI card into a blurry one.
    func uploadPrintImage(_ jpeg: Data) async throws -> URL {
        let payload: [String: String] = [
            "image": jpeg.base64EncodedString(),
            "filename": "postcard-print.jpg"
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await request(WidgetAPIRequest(.post, "widgets/postcard/mail/upload", body: body))
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let urlString = json?["imageUrl"] as? String, let url = URL(string: urlString) else {
            throw WidgetAPIError(status: 500, message: "Bad upload URL")
        }
        return url
    }

    // MARK: - Payment

    /// Apple Pay only, and this asks whether the DEVICE can pay — not whether
    /// a card is already in Wallet.
    ///
    /// It used to ask `StripeAPI.deviceSupportsApplePay()`, which returns false
    /// when Wallet is empty. That hid the paid postcard option outright on any
    /// device with no card set up, which is every fresh device — including the
    /// iPad App Review tested 1.3.3 on, so the review found no Apple Pay
    /// anywhere in the app and rejected it under Guideline 2.1. Someone with an
    /// empty Wallet is offered the option and sent to Wallet to add a card (see
    /// `collectPayment`), which is what Apple expects.
    var supportsPayment: Bool { PKPaymentAuthorizationController.canMakePayments() }

    /// The account's quiet hours, so widget-scheduled local reminders stay
    /// silent when the server's pushes would.
    var quietHours: WidgetQuietHours? {
        guard let prefs = AuthService.shared.currentUser?.notificationPreferences, prefs.quietHoursEnabled else { return nil }
        return WidgetQuietHours(start: prefs.quietHoursStart, end: prefs.quietHoursEnd)
    }

    /// Presents the wallet and waits for the person to finish with it. Must
    /// be reached straight from their tap — Apple won't present the sheet
    /// after asynchronous work, which is why the order is created inside it.
    @MainActor
    func collectPayment(_ request: WidgetPaymentRequest) async throws -> WidgetPaymentResult {
        guard let presenter = presentingViewController else {
            throw WidgetAPIError(status: 500, code: "no_presenter", message: "Couldn't show Apple Pay.")
        }
        // The option is offered on any Apple Pay device, so this is where an
        // empty Wallet is handled: send them to add a card rather than
        // presenting a sheet that can't be paid. `openPaymentSetup` returns
        // immediately — the card is added in Wallet, then they come back and
        // tap Send again.
        guard StripeAPI.deviceSupportsApplePay() else {
            PKPassLibrary().openPaymentSetup()
            throw WidgetAPIError(status: 400, code: "apple_pay_no_card",
                                 message: "Add a card to Apple Wallet, then tap Send again.")
        }
        let coordinator = ApplePayCoordinator(clientSecret: request.clientSecret)
        return try await coordinator.present(request, from: presenter)
    }

    // MARK: - Widget API channel

    /// Authenticated raw call for widget-owned endpoints. Only `widgets/`
    /// paths are allowed; the widget package never sees the token.
    func request(_ request: WidgetAPIRequest) async throws -> Data {
        guard request.path.hasPrefix("widgets/"), !request.path.contains("..") else {
            throw WidgetAPIError(status: 403, message: "Path not allowed")
        }
        guard let token = KeychainService.shared.getAuthToken(), !token.isEmpty else {
            throw WidgetAPIError(status: 401, message: "Sign in to continue")
        }
        guard let url = URL(string: "\(APIEnvironment.current.baseURL)/\(request.path)") else {
            throw WidgetAPIError(status: 400, message: "Bad request")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (body?["message"] as? String) ?? (body?["error"] as? String) ?? "Request failed (\(status))"
            throw WidgetAPIError(status: status, code: body?["code"] as? String, message: message)
        }
        return data
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

/// Thread-safe "first caller wins" flag for one-shot callbacks.
final class OnceFlag {
    private let lock = NSLock()
    private var claimed = false
    /// True exactly once.
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
