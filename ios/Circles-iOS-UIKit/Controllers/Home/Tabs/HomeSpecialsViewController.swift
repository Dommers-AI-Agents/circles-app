import UIKit
import MapKit
import SafariServices

/// The home screen's Specials tab: live offers and announcements from
/// participating venues, one row per deal in the server's order (saved
/// venues first, then nearest), then "Happening nearby" — concerts, games
/// and shows from Ticketmaster (Wes, 2026-10-15). Loads once when first
/// shown; pull-to-refresh and the `specialsUpdated` SSE event refetch.
final class HomeSpecialsViewController: BaseViewController, HomeContentTab {
    weak var host: HomeContentTabHost?
    var isActiveTab = false

    private(set) var specials: [SpecialItem] = []
    private(set) var events: [NearbyEvent] = []
    private var isLoadingSpecials = false

    private enum Section: Int, CaseIterable { case specials, events }
    /// A fetch finished since the last invalidate — an empty answer counts,
    /// so a quiet day doesn't refetch behind a spinner on every tap.
    private var hasLoaded = false

    let tableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = Constants.Colors.background
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 92
        tableView.showsVerticalScrollIndicator = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    private let statusView = HomeTabStatusView()

    // The host's segment switch drives loading; nothing loads on its own.
    override var loadsDataOnViewDidLoad: Bool { false }
    override var reloadsDataOnAppear: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        view.addSubview(tableView)
        view.addSubview(statusView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.topAnchor.constraint(equalTo: view.topAnchor),
            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SpecialItemCell.self, forCellReuseIdentifier: SpecialItemCell.identifier)
        tableView.register(NearbyEventCell.self, forCellReuseIdentifier: NearbyEventCell.identifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "note")
        tableView.sectionHeaderTopPadding = 0
    }

    // MARK: - HomeContentTab

    func tabDidBecomeVisible() {
        // Load once; pull-to-refresh refetches. Last time's list paints
        // straight away while the fresh one loads.
        guard !hasLoaded else { return }
        if specials.isEmpty, events.isEmpty {
            if let cached: RewardOffersData = SpecialsCache.load("specials") { apply(cached) }
            if let cached: [NearbyEvent] = SpecialsCache.load("nearby-events") { applyEvents(cached) }
        }
        fetchSpecials()
    }

    func tabWillHide() {}

    func refreshTab() {
        fetchSpecials(force: true)
    }

    /// A venue changed its offers while this tab was hidden: drop the loaded
    /// list so the next visit refetches.
    func invalidate() {
        hasLoaded = false
    }

    // MARK: - Loading

    /// Loads live deals from participating venues (flattened into one row
    /// per offer/announcement, in the server's venue order) and nearby
    /// events, side by side; each section fills in as it lands.
    func fetchSpecials(force: Bool = false) {
        guard !isLoadingSpecials else { return }
        isLoadingSpecials = true

        if specials.isEmpty && events.isEmpty {
            statusView.isLoading = true
        }

        // Location improves ordering but is optional — denied/unavailable
        // falls back to the server's alphabetical order (and no events). A
        // recent fix is plenty for "nearest first"; never wait on the GPS.
        LocationService.shared.recentLocation { [weak self] location in
            let group = DispatchGroup()
            var offersOK = false

            group.enter()
            RewardsService.shared.getOffers(
                lat: location?.coordinate.latitude,
                lng: location?.coordinate.longitude
            ) { result in
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard let self, case .success(let data) = result else { return }
                    offersOK = true
                    self.apply(data)
                    SpecialsCache.save(data, as: "specials")
                }
            }

            if let location {
                group.enter()
                RewardsService.shared.getNearbyEvents(lat: location.coordinate.latitude,
                                                      lng: location.coordinate.longitude) { result in
                    DispatchQueue.main.async {
                        defer { group.leave() }
                        // A failed refresh keeps what's showing
                        guard let self, case .success(let events) = result else { return }
                        self.applyEvents(events)
                        SpecialsCache.save(events, as: "nearby-events")
                    }
                }
            }

            group.notify(queue: .main) {
                guard let self else { return }
                self.isLoadingSpecials = false
                self.statusView.isLoading = false
                self.host?.endRefreshing()
                if offersOK { self.hasLoaded = true }
                self.updateStatusMessage(failed: !offersOK)
            }
        }
    }

    private func apply(_ data: RewardOffersData) {
        specials = data.venues.flatMap { venue -> [SpecialItem] in
            let offerItems = venue.offers.map {
                SpecialItem(venue: venue, kind: .offer($0))
            }
            let announcementItems = (venue.announcements ?? []).map {
                SpecialItem(venue: venue, kind: .announcement($0))
            }
            return offerItems + announcementItems
        }
        tableView.reloadData()
        if !specials.isEmpty || !events.isEmpty { statusView.isLoading = false; statusView.message = nil }
    }

    private func applyEvents(_ events: [NearbyEvent]) {
        self.events = events
        tableView.reloadData()
        if !events.isEmpty { statusView.isLoading = false; statusView.message = nil }
    }

    private func updateStatusMessage(failed: Bool) {
        guard specials.isEmpty && events.isEmpty else {
            statusView.message = nil
            return
        }
        statusView.message = failed
            ? "Couldn't load specials — pull to refresh"
            : "No specials right now. Deals from places on your map and nearby show up here."
    }

    /// The event's own page (tickets, details) in an in-app browser.
    func openEvent(_ event: NearbyEvent) {
        guard let url = URL(string: event.url) else { return }
        AnalyticsService.shared.logEvent("nearby_event_opened", parameters: ["category": event.category ?? "none"])
        present(SFSafariViewController(url: url), animated: true)
    }

    /// Apple Maps directions to the event's venue.
    func openEventDirections(_ event: NearbyEvent) {
        guard let lat = event.lat, let lng = event.lng else { return }
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)))
        mapItem.name = event.venueName ?? event.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    /// One bubble: the event's link.
    func shareEvent(_ event: NearbyEvent) {
        guard let url = URL(string: event.url) else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = tableView
        present(activityVC, animated: true)
    }

    // MARK: - Actions

    /// Opens the tapped deal's place page — same resolution as the Rewards
    /// screen: canonical global place by id, venue-built fallback otherwise.
    func openSpecialPlace(_ venue: OfferVenue) {
        guard let placeId = venue.globalPlaceId ?? venue.googlePlaceId else {
            pushSpecialPlaceFallback(venue)
            return
        }

        let loading = AlertPresenter.showLoading(message: "Loading place...", from: self)
        GlobalPlaceService.shared.getGlobalPlace(id: placeId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let response):
                        let place = response.bestDetailPlace()
                        let detailVC = PlaceDetailViewController(place: place)
                        self.navigationController?.pushViewController(detailVC, animated: true)
                    case .failure:
                        self.pushSpecialPlaceFallback(venue)
                    }
                }
            }
        }
    }

    /// Long-press share on a row: the deal's text plus the venue's place link
    /// (or the App Store link when the venue has no linked place)
    func shareSpecial(_ item: SpecialItem) {
        var shareText: String
        switch item.kind {
        case .offer(let offer):
            shareText = "🎁 \(offer.title) at \(item.venue.venueName) — redeem it with points on FavCircles!"
        case .announcement(let announcement):
            shareText = "📣 \(announcement.title) at \(item.venue.venueName)"
            if !announcement.message.isEmpty {
                shareText += "\n\(announcement.message)"
            }
            shareText += "\nSeen on FavCircles:"
        }

        // The /place page resolves both save-doc and globalPlaces ids — a
        // googlePlaceId won't resolve, so fall back to the App Store link
        let url: URL = item.venue.globalPlaceId.map { ShareLinks.place(id: $0) } ?? ShareLinks.appStoreURL

        let activityVC = UIActivityViewController(activityItems: [shareText, url], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = tableView
        present(activityVC, animated: true)
    }

    private func pushSpecialPlaceFallback(_ venue: OfferVenue) {
        var location: GeoLocation?
        if let coordinate = venue.location {
            // GeoJSON order: [longitude, latitude]
            location = GeoLocation(type: "Point", coordinates: [coordinate.lng, coordinate.lat])
        }

        let place = Place(
            id: venue.globalPlaceId ?? venue.googlePlaceId ?? venue.venueId,
            globalPlaceId: venue.globalPlaceId,
            name: venue.placeName ?? venue.venueName,
            description: nil,
            address: venue.placeAddress ?? "",
            location: location,
            website: nil,
            phone: nil,
            googlePlaceId: venue.googlePlaceId,
            photos: nil,
            videos: nil,
            category: PlaceCategory(rawValue: venue.category ?? "") ?? .restaurant,
            customCategoryId: nil,
            subcategory: nil,
            rating: nil,
            userRatingsTotal: nil,
            notes: nil,
            privateNotes: nil,
            publicNotes: nil,
            tags: nil,
            reviews: nil,
            openingHours: nil,
            priceLevel: nil,
            likes: nil,
            likesCount: nil,
            commentsCount: nil,
            circleId: nil,
            addedBy: "",
            addedByUser: nil,
            privacy: .public,
            createdAt: Date(),
            updatedAt: Date()
        )
        let detailVC = PlaceDetailViewController(place: place)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - Table

extension HomeSpecialsViewController: UITableViewDelegate, UITableViewDataSource {
    /// No store deals but events to show: one quiet line says so.
    private var showsNoSpecialsNote: Bool { specials.isEmpty && !events.isEmpty }

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .specials: return showsNoSpecialsNote ? 1 : specials.count
        case .events: return events.count
        case nil: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == Section.events.rawValue {
            let cell = tableView.dequeueReusableCell(withIdentifier: NearbyEventCell.identifier, for: indexPath) as! NearbyEventCell
            guard indexPath.row < events.count else { return cell }
            cell.configure(with: events[indexPath.row])
            return cell
        }
        if showsNoSpecialsNote {
            let cell = tableView.dequeueReusableCell(withIdentifier: "note", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "No store specials nearby right now."
            content.textProperties.font = .systemFont(ofSize: 14)
            content.textProperties.color = Constants.Colors.secondaryLabel
            cell.contentConfiguration = content
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: SpecialItemCell.identifier, for: indexPath) as! SpecialItemCell
        guard indexPath.row < specials.count else { return cell }
        cell.configure(with: specials[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == Section.events.rawValue, !events.isEmpty else { return nil }
        let label = UILabel()
        label.text = "Happening nearby"
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = Constants.Colors.label
        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: specials.isEmpty && !showsNoSpecialsNote ? 8 : 20),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == Section.events.rawValue && !events.isEmpty ? UITableView.automaticDimension : .leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == Section.events.rawValue, !events.isEmpty else { return nil }
        let label = UILabel()
        label.text = "Events from Ticketmaster"
        label.font = .systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        return label
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        section == Section.events.rawValue && !events.isEmpty ? 36 : .leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == Section.events.rawValue {
            guard indexPath.row < events.count else { return }
            openEvent(events[indexPath.row])
            return
        }
        guard !showsNoSpecialsNote, indexPath.row < specials.count else { return }
        openSpecialPlace(specials[indexPath.row].venue)
    }

    // Long-press: share a deal (with the place link), or share / get
    // directions to an event
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        if indexPath.section == Section.events.rawValue {
            guard indexPath.row < events.count else { return nil }
            let event = events[indexPath.row]
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                var actions = [
                    UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                        self?.shareEvent(event)
                    }
                ]
                if event.lat != nil, event.lng != nil {
                    actions.append(UIAction(title: "Directions", image: UIImage(systemName: "car.fill")) { [weak self] _ in
                        self?.openEventDirections(event)
                    })
                }
                return UIMenu(children: actions)
            }
        }
        guard !showsNoSpecialsNote, indexPath.row < specials.count else { return nil }
        let item = specials[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.shareSpecial(item)
            }
            return UIMenu(children: [share])
        }
    }
}

/// Last lists per account, in Caches, so the tab opens on them.
private enum SpecialsCache {
    private static func url(_ name: String) -> URL? {
        guard let userId = AuthService.shared.getUserId() else { return nil }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("\(name)-\(userId).json")
    }

    static func load<T: Decodable>(_ name: String) -> T? {
        guard let url = url(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, as name: String) {
        guard let url = url(name), let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
