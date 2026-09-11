import UIKit

/// The home screen's Specials tab: live offers and announcements from
/// participating venues, one row per deal in the server's order (saved
/// venues first, then nearest). Loads once when first shown; pull-to-refresh
/// and the `specialsUpdated` SSE event refetch.
final class HomeSpecialsViewController: BaseViewController, HomeContentTab {
    weak var host: HomeContentTabHost?
    var isActiveTab = false

    private(set) var specials: [SpecialItem] = []
    private var isLoadingSpecials = false

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
    }

    // MARK: - HomeContentTab

    func tabDidBecomeVisible() {
        // Load once; pull-to-refresh refetches
        if specials.isEmpty {
            fetchSpecials()
        }
    }

    func tabWillHide() {}

    func refreshTab() {
        fetchSpecials(force: true)
    }

    /// A venue changed its offers while this tab was hidden: drop the loaded
    /// list so the next visit refetches.
    func invalidate() {
        specials = []
    }

    // MARK: - Loading

    /// Loads live deals from participating venues and flattens them into one
    /// row per offer/announcement, preserving the server's venue order.
    func fetchSpecials(force: Bool = false) {
        guard !isLoadingSpecials else { return }
        isLoadingSpecials = true

        if specials.isEmpty {
            statusView.isLoading = true
        }

        // Location improves ordering but is optional — denied/unavailable
        // falls back to the server's alphabetical order
        LocationService.shared.getCurrentLocation { [weak self] location in
            RewardsService.shared.getOffers(
                lat: location?.coordinate.latitude,
                lng: location?.coordinate.longitude
            ) { result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isLoadingSpecials = false
                    self.statusView.isLoading = false
                    self.host?.endRefreshing()

                    switch result {
                    case .success(let data):
                        self.specials = data.venues.flatMap { venue -> [SpecialItem] in
                            let offerItems = venue.offers.map {
                                SpecialItem(venue: venue, kind: .offer($0))
                            }
                            let announcementItems = (venue.announcements ?? []).map {
                                SpecialItem(venue: venue, kind: .announcement($0))
                            }
                            return offerItems + announcementItems
                        }
                        self.tableView.reloadData()
                        self.statusView.message = self.specials.isEmpty ? "No specials right now — check back soon" : nil

                    case .failure:
                        if self.specials.isEmpty {
                            self.statusView.message = "Couldn't load specials — pull to refresh"
                        }
                    }
                }
            }
        }
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
            shareText = "🎁 \(offer.title) at \(item.venue.venueName) — redeem it with points on Circles!"
        case .announcement(let announcement):
            shareText = "📣 \(announcement.title) at \(item.venue.venueName)"
            if !announcement.message.isEmpty {
                shareText += "\n\(announcement.message)"
            }
            shareText += "\nSeen on Circles:"
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
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        specials.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SpecialItemCell.identifier, for: indexPath) as! SpecialItemCell
        guard indexPath.row < specials.count else { return cell }
        cell.configure(with: specials[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < specials.count else { return }
        openSpecialPlace(specials[indexPath.row].venue)
    }

    // Long-press a row to share the deal (with the place link)
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.row < specials.count else { return nil }
        let item = specials[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.shareSpecial(item)
            }
            return UIMenu(children: [share])
        }
    }
}
