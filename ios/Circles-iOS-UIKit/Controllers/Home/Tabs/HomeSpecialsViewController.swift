import UIKit
import MapKit
import SafariServices

/// The home screen's Locals tab (was Specials): live offers and announcements
/// from participating venues in the server's order (saved venues first, then
/// nearest), one row per store: a store with several deals opens to list them
/// (Wes, 2026-11-05). A deal opens the store's rewards page; then "Happening nearby" — events stores post
/// on FavCircles, free library programs and Ticketmaster shows — and the
/// nearest farmers markets (Wes, 2026-10-15). Loads once when first shown;
/// pull-to-refresh and the `specialsUpdated` SSE event refetch.
final class HomeSpecialsViewController: BaseViewController, HomeContentTab {
    weak var host: HomeContentTabHost?
    var isActiveTab = false

    private(set) var specials: [SpecialItem] = []
    /// Stores whose deals are open
    private var expandedStores: Set<String> = []
    private(set) var events: [NearbyEvent] = []
    private(set) var markets: [FarmersMarket] = []
    /// The server's credits line for the sources shown
    private var attribution: String?
    private var isLoadingSpecials = false

    private enum Section: Int, CaseIterable { case searchNote, specials, events, markets }

    // MARK: Search (Wes, 2026-11-04: "Panthers football")
    /// The words in the box; empty = the normal tab
    private var searchQuery = ""
    private var isSearchActive: Bool { !LocalsSearch.words(searchQuery).isEmpty }
    /// The server's answer for `remoteQuery` (nil while it's out or not asked)
    private var remoteResults: [NearbyEvent]?
    private var remoteQuery = ""
    private var remoteNearby = true
    private var remoteAttribution: String?
    private var isSearchingRemote = false
    private var searchWork: DispatchWorkItem?

    private lazy var searchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.placeholder = "Search events, teams, shows"
        bar.searchBarStyle = .minimal
        bar.autocapitalizationType = .none
        bar.returnKeyType = .search
        bar.delegate = self
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    /// What the table draws: everything, or the matches for the box
    var shownSpecials: [SpecialItem] {
        guard isSearchActive else { return specials }
        return specials.filter {
            LocalsSearch.matches([$0.title, $0.venue.venueName, $0.venue.placeName, $0.venue.category], query: searchQuery)
        }
    }
    /// The deals section's rows: one per store, open stores followed by their
    /// deals. A search opens every store, so each match shows.
    var dealRows: [LocalsDealGrouping.Row<SpecialItem>] {
        LocalsDealGrouping.rows(shownSpecials, key: { $0.venue.venueId }, expanded: expandedStores, expandAll: isSearchActive)
    }
    var shownEvents: [NearbyEvent] {
        guard isSearchActive else { return events }
        let local = events.filter { LocalsSearch.matches($0, query: searchQuery) }
        guard let remoteResults, remoteQuery == trimmedQuery else { return local }
        return LocalsSearch.mergeEvents(local: local, remote: remoteResults)
    }
    var shownMarkets: [FarmersMarket] {
        guard isSearchActive else { return markets }
        return markets.filter { LocalsSearch.matches([$0.name, $0.address], query: searchQuery) }
    }
    private var trimmedQuery: String { searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The one line over search results: still looking, nothing found, or
    /// nothing near so these are from anywhere
    var searchNoteText: String? {
        guard isSearchActive else { return nil }
        let nothing = shownSpecials.isEmpty && shownEvents.isEmpty && shownMarkets.isEmpty
        if nothing {
            if isSearchingRemote || (trimmedQuery.count >= LocalsSearch.minRemoteLength && remoteQuery != trimmedQuery) {
                return "Searching events…"
            }
            return "Nothing matches “\(trimmedQuery)”. Try a team, artist or venue."
        }
        if remoteQuery == trimmedQuery, remoteResults?.isEmpty == false, !remoteNearby {
            return "Nothing within 100 miles. These are happening elsewhere."
        }
        return nil
    }
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
        view.addSubview(searchBar)
        view.addSubview(tableView)
        view.addSubview(statusView)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            statusView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            statusView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SpecialItemCell.self, forCellReuseIdentifier: SpecialItemCell.identifier)
        tableView.register(NearbyEventCell.self, forCellReuseIdentifier: NearbyEventCell.identifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "note")
        tableView.sectionHeaderTopPadding = 0
        tableView.keyboardDismissMode = .onDrag
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

    func tabWillHide() {
        searchBar.resignFirstResponder()
    }

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

        // Nearest first from where they are; without a fix (denied or not
        // yet), from Charlotte, the default location. A recent fix is plenty
        // for "nearest first"; never wait on the GPS.
        LocationService.shared.recentLocation { [weak self] location in
            let here = location?.coordinate ?? Constants.DefaultLocation.coordinate
            let group = DispatchGroup()
            var offersOK = false

            group.enter()
            RewardsService.shared.getOffers(
                lat: here.latitude,
                lng: here.longitude
            ) { result in
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard let self, case .success(let data) = result else { return }
                    offersOK = true
                    self.apply(data)
                    SpecialsCache.save(data, as: "specials")
                }
            }

            group.enter()
            RewardsService.shared.getNearbyEvents(lat: here.latitude, lng: here.longitude) { result in
                DispatchQueue.main.async {
                    defer { group.leave() }
                    // A failed refresh keeps what's showing
                    guard let self, case .success(let feed) = result else { return }
                    self.applyFeed(feed)
                    SpecialsCache.save(feed, as: "local-feed")
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
        guard !isSearchActive, specials.isEmpty && events.isEmpty && markets.isEmpty else {
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
                            subcategory: "Farmers market",
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

    /// One bubble: the event's card (what, when, where, price) opening its
    /// venue's place page in FavCircles, not the ticket site (Wes, 2026-11-12)
    func shareEvent(_ event: NearbyEvent) {
        PlaceShareController.share(event: event, from: self, sourceView: tableView)
    }

    /// One bubble: the market's card (days, hours, where) opening its place page
    func shareMarket(_ market: FarmersMarket) {
        PlaceShareController.share(market: market, from: self, sourceView: tableView)
    }

    // MARK: - Actions

    /// A deal opens its store's rewards page to look through (Wes,
    /// 2026-11-05); the store's name there opens its place page. The
    /// canonical place and the store's rewards load side by side; a store
    /// with no rewards to get opens its place page instead.
    func openStoreRewards(_ venue: OfferVenue) {
        guard let placeId = venue.globalPlaceId ?? venue.googlePlaceId else {
            pushSpecialPlaceFallback(venue)
            return
        }
        AnalyticsService.shared.logEvent("locals_deal_opened", parameters: ["venue": venue.venueId])
        let loading = AlertPresenter.showLoading(message: "Loading rewards...", from: self)
        let group = DispatchGroup()
        var place: Place?
        var data: PlaceVenueData?
        group.enter()
        GlobalPlaceService.shared.getGlobalPlace(id: placeId) { result in
            DispatchQueue.main.async {
                if case .success(let response) = result { place = response.bestDetailPlace() }
                group.leave()
            }
        }
        group.enter()
        RewardsService.shared.getVenueByPlace(placeId: placeId, googlePlaceId: venue.googlePlaceId) { result in
            DispatchQueue.main.async {
                if case .success(let venueData) = result { data = venueData }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            loading.dismiss(animated: true) {
                guard let self else { return }
                let store = place ?? self.fallbackPlace(for: venue)
                let page: UIViewController = GetRewardsViewController(place: store, data: data)
                    ?? PlaceDetailViewController(place: store)
                self.navigationController?.pushViewController(page, animated: true)
            }
        }
    }

    /// Opens or closes a store's deals in place. Opening scrolls the store to
    /// the top and tints its deals so it's clear what the tap showed.
    private func toggleStore(_ key: String, at headerPath: IndexPath) {
        let before = dealRows.count
        let opening = !expandedStores.contains(key)
        if opening { expandedStores.insert(key) } else { expandedStores.remove(key) }
        let added = dealRows.count - before
        let childPaths = (1...max(1, abs(added))).map { IndexPath(row: headerPath.row + $0, section: headerPath.section) }
        guard added != 0 else {
            tableView.reloadData()
            return
        }
        tableView.performBatchUpdates {
            if opening {
                tableView.insertRows(at: childPaths, with: .fade)
            } else {
                tableView.deleteRows(at: childPaths, with: .fade)
            }
            tableView.reloadRows(at: [headerPath], with: .none)
        } completion: { [weak self] _ in
            guard let self, opening else { return }
            self.tableView.scrollToRow(at: headerPath, at: .top, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                childPaths.forEach { (self.tableView.cellForRow(at: $0) as? SpecialItemCell)?.flashReveal() }
            }
        }
        if !opening, !(tableView.indexPathsForVisibleRows ?? []).contains(headerPath) {
            tableView.scrollToRow(at: headerPath, at: .top, animated: true)
        }
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

    /// Long-press share on a row: one bubble, the deal's card opening the
    /// store's place page (2026-11-12)
    func shareSpecial(_ item: SpecialItem) {
        let venue = item.venue
        let content = PlaceShareCopy.content(for: item)
        let target = PlaceShareCopy.target(id: "", globalPlaceId: venue.globalPlaceId,
                                           googlePlaceId: venue.googlePlaceId, addedBy: "")
        let mint = PlaceShareController.MintDetails(name: venue.placeName ?? venue.venueName, address: venue.placeAddress,
                                                    lat: venue.location?.lat, lng: venue.location?.lng,
                                                    category: PlaceCategory(rawValue: venue.category ?? "") ?? .restaurant)
        PlaceShareController.share(content: content, target: target, mint: mint, from: self, sourceView: tableView)
    }

    private func pushSpecialPlaceFallback(_ venue: OfferVenue) {
        navigationController?.pushViewController(PlaceDetailViewController(place: fallbackPlace(for: venue)), animated: true)
    }

    /// The store as the deal row knows it, when its place record can't load
    private func fallbackPlace(for venue: OfferVenue) -> Place {
        makePlace(name: venue.placeName ?? venue.venueName, address: venue.placeAddress,
                  lat: venue.location?.lat, lng: venue.location?.lng,
                  globalPlaceId: venue.globalPlaceId, googlePlaceId: venue.googlePlaceId,
                  id: venue.venueId, category: PlaceCategory(rawValue: venue.category ?? "") ?? .restaurant,
                  photos: venue.photoUrl.map { [$0] })
    }

    /// A place page built from what the row knows (no saved record behind it).
    private func pushPlace(name: String, address: String?, lat: Double?, lng: Double?,
                           globalPlaceId: String?, googlePlaceId: String?,
                           id: String? = nil, category: PlaceCategory = .restaurant, subcategory: String? = nil,
                           photos: [String]? = nil, website: String? = nil, openingHours: [OpeningHour]? = nil) {
        let place = makePlace(name: name, address: address, lat: lat, lng: lng, globalPlaceId: globalPlaceId,
                              googlePlaceId: googlePlaceId, id: id, category: category, subcategory: subcategory, photos: photos,
                              website: website, openingHours: openingHours)
        navigationController?.pushViewController(PlaceDetailViewController(place: place), animated: true)
    }

    private func makePlace(name: String, address: String?, lat: Double?, lng: Double?,
                           globalPlaceId: String?, googlePlaceId: String?,
                           id: String? = nil, category: PlaceCategory = .restaurant, subcategory: String? = nil,
                           photos: [String]? = nil, website: String? = nil, openingHours: [OpeningHour]? = nil) -> Place {
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
            subcategory: subcategory,
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
        return place
    }
}

// MARK: - Table

extension HomeSpecialsViewController: UITableViewDelegate, UITableViewDataSource {
    /// No store deals but other things to show: one quiet line says so.
    private var showsNoSpecialsNote: Bool { !isSearchActive && shownSpecials.isEmpty && (!shownEvents.isEmpty || !shownMarkets.isEmpty) }

    /// Search results credit what they show
    private var shownAttribution: String? { isSearchActive ? (remoteAttribution ?? attribution) : attribution }

    /// The credits line sits under the last section with rows.
    private var attributionSection: Section? {
        guard shownAttribution != nil else { return nil }
        if !shownMarkets.isEmpty { return .markets }
        return shownEvents.isEmpty ? nil : .events
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .searchNote: return searchNoteText == nil ? 0 : 1
        case .specials: return showsNoSpecialsNote ? 1 : dealRows.count
        case .events: return shownEvents.count
        case .markets: return shownMarkets.count
        case nil: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .searchNote:
            let cell = tableView.dequeueReusableCell(withIdentifier: "note", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = searchNoteText
            content.textProperties.font = .systemFont(ofSize: 14)
            content.textProperties.color = Constants.Colors.secondaryLabel
            cell.contentConfiguration = content
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            return cell
        case .events:
            let cell = tableView.dequeueReusableCell(withIdentifier: NearbyEventCell.identifier, for: indexPath) as! NearbyEventCell
            if indexPath.row < shownEvents.count { cell.configure(with: shownEvents[indexPath.row]) }
            return cell
        case .markets:
            let cell = tableView.dequeueReusableCell(withIdentifier: NearbyEventCell.identifier, for: indexPath) as! NearbyEventCell
            if indexPath.row < shownMarkets.count { cell.configure(with: shownMarkets[indexPath.row]) }
            return cell
        default:
            break
        }
        if showsNoSpecialsNote {
            let cell = tableView.dequeueReusableCell(withIdentifier: "note", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "No store deals nearby right now."
            content.textProperties.font = .systemFont(ofSize: 14)
            content.textProperties.color = Constants.Colors.secondaryLabel
            cell.contentConfiguration = content
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: SpecialItemCell.identifier, for: indexPath) as! SpecialItemCell
        let rows = dealRows
        guard indexPath.row < rows.count else { return cell }
        switch rows[indexPath.row] {
        case .single(let item): cell.configure(with: item)
        case .deal(let item): cell.configure(with: item, isStoreDeal: true)
        case .store(_, let items, let isExpanded): cell.configure(store: items, isExpanded: isExpanded)
        }
        return cell
    }

    private func headerTitle(_ section: Int) -> String? {
        switch Section(rawValue: section) {
        case .events: return shownEvents.isEmpty ? nil : (isSearchActive ? "Events" : "Happening nearby")
        case .markets: return shownMarkets.isEmpty ? nil : "Farmers markets"
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
        let isFirst = shownSpecials.isEmpty && !showsNoSpecialsNote && (section == Section.events.rawValue || shownEvents.isEmpty)
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
        guard Section(rawValue: section) == attributionSection, let attribution = shownAttribution else { return nil }
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
        case .searchNote:
            return
        case .events:
            if indexPath.row < shownEvents.count { openEvent(shownEvents[indexPath.row]) }
        case .markets:
            if indexPath.row < shownMarkets.count { openMarket(shownMarkets[indexPath.row]) }
        default:
            let rows = dealRows
            guard !showsNoSpecialsNote, indexPath.row < rows.count else { return }
            switch rows[indexPath.row] {
            case .single(let item), .deal(let item): openStoreRewards(item.venue)
            case .store(let key, let items, _):
                // A search shows every store open already: the header opens the store
                if isSearchActive, let first = items.first { openStoreRewards(first.venue) } else { toggleStore(key, at: indexPath) }
            }
        }
    }

    // Long-press: share a deal (with the place link); share or get
    // directions to an event or a market
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        switch Section(rawValue: indexPath.section) {
        case .searchNote:
            return nil
        case .events:
            guard indexPath.row < shownEvents.count else { return nil }
            let event = shownEvents[indexPath.row]
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
            guard indexPath.row < shownMarkets.count else { return nil }
            let market = shownMarkets[indexPath.row]
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                UIMenu(children: [
                    UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                        self?.shareMarket(market)
                    },
                    UIAction(title: "Directions", image: UIImage(systemName: "car.fill")) { [weak self] _ in
                        self?.openMarketDirections(market)
                    }
                ])
            }
        default:
            let rows = dealRows
            guard !showsNoSpecialsNote, indexPath.row < rows.count else { return nil }
            let item: SpecialItem
            switch rows[indexPath.row] {
            case .single(let deal), .deal(let deal): item = deal
            case .store: return nil
            }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                    self?.shareSpecial(item)
                }
                return UIMenu(children: [share])
            }
        }
    }
}

// MARK: - Search

extension HomeSpecialsViewController: UISearchBarDelegate {
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchQuery = searchText
        searchWork?.cancel()
        let query = trimmedQuery
        if query.count >= LocalsSearch.minRemoteLength, query != remoteQuery {
            let work = DispatchWorkItem { [weak self] in self?.runRemoteSearch(query) }
            searchWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + LocalsSearch.debounce, execute: work)
        }
        showSearchState()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchWork?.cancel()
        let query = trimmedQuery
        if query.count >= LocalsSearch.minRemoteLength, query != remoteQuery { runRemoteSearch(query) }
        searchBar.resignFirstResponder()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        self.searchBar(searchBar, textDidChange: "")
        searchBar.resignFirstResponder()
    }

    private func runRemoteSearch(_ query: String) {
        isSearchingRemote = true
        AnalyticsService.shared.logEvent("locals_search", parameters: ["length": "\(query.count)"])
        LocationService.shared.recentLocation { [weak self] location in
            let here = location?.coordinate ?? Constants.DefaultLocation.coordinate
            RewardsService.shared.searchNearbyEvents(query: query, lat: here.latitude, lng: here.longitude) { result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    // A newer query owns the screen; this answer is stale
                    guard query == self.trimmedQuery else { return }
                    self.isSearchingRemote = false
                    if case .success(let data) = result {
                        self.remoteResults = data.events
                        self.remoteNearby = data.nearby ?? true
                        self.remoteAttribution = data.attribution
                    } else {
                        self.remoteResults = []
                        self.remoteNearby = true
                        self.remoteAttribution = nil
                    }
                    self.remoteQuery = query
                    self.showSearchState()
                }
            }
        }
    }

    private func showSearchState() {
        if !isSearchActive { statusView.message = nil; updateStatusMessage(failed: false) } else { statusView.message = nil }
        tableView.reloadData()
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
