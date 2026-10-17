import UIKit
import MapKit
import SafariServices

/// The home screen's Locals tab (was Specials): live offers and announcements
/// from participating venues, one row per deal in the server's order (saved
/// venues first, then nearest); then "Happening nearby" — events stores post
/// on FavCircles, free library programs and Ticketmaster shows — and the
/// nearest farmers markets (Wes, 2026-10-15). Loads once when first shown;
/// pull-to-refresh and the `specialsUpdated` SSE event refetch.
final class HomeSpecialsViewController: BaseViewController, HomeContentTab {
    weak var host: HomeContentTabHost?
    var isActiveTab = false

    private(set) var specials: [SpecialItem] = []
    private(set) var events: [NearbyEvent] = []
    private(set) var markets: [FarmersMarket] = []
    /// The server's credits line for the sources shown
    private var attribution: String?
    private var isLoadingSpecials = false

    private enum Section: Int, CaseIterable { case specials, events, markets }
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
            if let cached: NearbyEventsData = SpecialsCache.load("local-feed") { applyFeed(cached) }
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

        if specials.isEmpty && events.isEmpty && markets.isEmpty {
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
                        guard let self, case .success(let feed) = result else { return }
                        self.applyFeed(feed)
                        SpecialsCache.save(feed, as: "local-feed")
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

    private func applyFeed(_ feed: NearbyEventsData) {
        events = feed.events
        markets = feed.markets ?? []
        attribution = feed.attribution
        tableView.reloadData()
        if !events.isEmpty || !markets.isEmpty { statusView.isLoading = false; statusView.message = nil }
    }

    private func updateStatusMessage(failed: Bool) {
        guard specials.isEmpty && events.isEmpty && markets.isEmpty else {
            statusView.message = nil
            return
        }
        statusView.message = failed
            ? "Couldn't load specials — pull to refresh"
            : "No specials right now. Deals from places on your map and nearby show up here."
    }

    /// A store's event opens the store's place page; anything else opens
    /// its own page (tickets, details) in an in-app browser.
    func openEvent(_ event: NearbyEvent) {
        AnalyticsService.shared.logEvent("nearby_event_opened", parameters: [
            "source": event.source ?? "ticketmaster", "category": event.category ?? "none"
        ])
        if event.isStoreEvent, let placeId = event.globalPlaceId ?? event.googlePlaceId {
            openPlace(id: placeId) { [weak self] in
                self?.pushPlace(name: event.venueName ?? event.name, address: event.venueAddress,
                                lat: event.lat, lng: event.lng, globalPlaceId: event.globalPlaceId, googlePlaceId: event.googlePlaceId)
            }
            return
        }
        guard let url = URL(string: event.url) else { return }
        present(SFSafariViewController(url: url), animated: true)
    }

    /// A market's place page: save it, see photos, get directions.
    func openMarket(_ market: FarmersMarket) {
        AnalyticsService.shared.logEvent("farmers_market_opened", parameters: ["google": market.googlePlaceId == nil ? "0" : "1"])
        let fallback: () -> Void = { [weak self] in
            self?.pushPlace(name: market.name, address: market.address, lat: market.lat, lng: market.lng,
                            globalPlaceId: nil, googlePlaceId: market.googlePlaceId, category: .retail,
                            photos: market.photoUrl.map { [$0] }, website: market.website, openingHours: market.openingHours)
        }
        // The real place page (days, hours, photos) when Google knows the market
        guard let googlePlaceId = market.googlePlaceId else {
            fallback()
            return
        }
        openPlace(id: googlePlaceId, fallback: fallback)
    }

    func openMarketDirections(_ market: FarmersMarket) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: market.lat, longitude: market.lng)))
        mapItem.name = market.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
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
        openPlace(id: placeId) { [weak self] in self?.pushSpecialPlaceFallback(venue) }
    }

    /// The canonical place page by id, or `fallback` when it can't load.
    private func openPlace(id placeId: String, fallback: @escaping () -> Void) {
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
                        fallback()
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
        pushPlace(name: venue.placeName ?? venue.venueName, address: venue.placeAddress,
                  lat: venue.location?.lat, lng: venue.location?.lng,
                  globalPlaceId: venue.globalPlaceId, googlePlaceId: venue.googlePlaceId,
                  id: venue.venueId, category: PlaceCategory(rawValue: venue.category ?? "") ?? .restaurant)
    }

    /// A place page built from what the row knows (no saved record behind it).
    private func pushPlace(name: String, address: String?, lat: Double?, lng: Double?,
                           globalPlaceId: String?, googlePlaceId: String?,
                           id: String? = nil, category: PlaceCategory = .restaurant,
                           photos: [String]? = nil, website: String? = nil, openingHours: [OpeningHour]? = nil) {
        var location: GeoLocation?
        if let lat, let lng {
            // GeoJSON order: [longitude, latitude]
            location = GeoLocation(type: "Point", coordinates: [lng, lat])
        }

        let place = Place(
            id: globalPlaceId ?? googlePlaceId ?? id ?? "local-\(name.lowercased().filter { $0.isLetter || $0.isNumber })",
            globalPlaceId: globalPlaceId,
            name: name,
            description: nil,
            address: address ?? "",
            location: location,
            website: website,
            phone: nil,
            googlePlaceId: googlePlaceId,
            photos: photos,
            videos: nil,
            category: category,
            customCategoryId: nil,
            subcategory: nil,
            rating: nil,
            userRatingsTotal: nil,
            notes: nil,
            privateNotes: nil,
            publicNotes: nil,
            tags: nil,
            reviews: nil,
            openingHours: openingHours,
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
    /// No store deals but other things to show: one quiet line says so.
    private var showsNoSpecialsNote: Bool { specials.isEmpty && (!events.isEmpty || !markets.isEmpty) }

    /// The credits line sits under the last section with rows.
    private var attributionSection: Section? {
        guard attribution != nil else { return nil }
        if !markets.isEmpty { return .markets }
        return events.isEmpty ? nil : .events
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .specials: return showsNoSpecialsNote ? 1 : specials.count
        case .events: return events.count
        case .markets: return markets.count
        case nil: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .events:
            let cell = tableView.dequeueReusableCell(withIdentifier: NearbyEventCell.identifier, for: indexPath) as! NearbyEventCell
            if indexPath.row < events.count { cell.configure(with: events[indexPath.row]) }
            return cell
        case .markets:
            let cell = tableView.dequeueReusableCell(withIdentifier: NearbyEventCell.identifier, for: indexPath) as! NearbyEventCell
            if indexPath.row < markets.count { cell.configure(with: markets[indexPath.row]) }
            return cell
        default:
            break
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

    private func headerTitle(_ section: Int) -> String? {
        switch Section(rawValue: section) {
        case .events: return events.isEmpty ? nil : "Happening nearby"
        case .markets: return markets.isEmpty ? nil : "Farmers markets"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = headerTitle(section) else { return nil }
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = Constants.Colors.label
        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        let isFirst = specials.isEmpty && !showsNoSpecialsNote && (section == Section.events.rawValue || events.isEmpty)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: isFirst ? 8 : 20),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        headerTitle(section) == nil ? .leastNormalMagnitude : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard Section(rawValue: section) == attributionSection, let attribution else { return nil }
        let label = UILabel()
        label.text = attribution
        label.font = .systemFont(ofSize: 11)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        Section(rawValue: section) == attributionSection ? UITableView.automaticDimension : .leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .events:
            if indexPath.row < events.count { openEvent(events[indexPath.row]) }
        case .markets:
            if indexPath.row < markets.count { openMarket(markets[indexPath.row]) }
        default:
            guard !showsNoSpecialsNote, indexPath.row < specials.count else { return }
            openSpecialPlace(specials[indexPath.row].venue)
        }
    }

    // Long-press: share a deal (with the place link); share or get
    // directions to an event or a market
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        switch Section(rawValue: indexPath.section) {
        case .events:
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
        case .markets:
            guard indexPath.row < markets.count else { return nil }
            let market = markets[indexPath.row]
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                UIMenu(children: [
                    UIAction(title: "Directions", image: UIImage(systemName: "car.fill")) { [weak self] _ in
                        self?.openMarketDirections(market)
                    }
                ])
            }
        default:
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
