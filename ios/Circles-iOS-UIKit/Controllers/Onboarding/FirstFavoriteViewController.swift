import UIKit
import MapKit
import CoreLocation

/// First step after the name (Wes, 2026-10-31: "I want a user's first use
/// to feel personal"): "What's the one place near you that you love most?"
/// Search or tap a quick pick, confirm, and it's saved into Favorite Local
/// Spots through the normal save path (coin drop, Mapmaker badge, canonical
/// venue). Then "Your place, your people". Skippable.
final class FirstFavoriteViewController: BaseViewController {

    override var showsLoadingIndicator: Bool { false }
    override var loadsDataOnViewDidLoad: Bool { false }

    /// The saved place's name, or nil when they skipped. Fired once.
    var onCompletion: ((String?) -> Void)?
    private var didComplete = false

    // MARK: - Gate

    private static func shownKey(_ userId: String) -> String { "firstFavoriteShown_\(userId)" }
    static func savedNameKey(_ userId: String) -> String { "firstFavoriteName_\(userId)" }

    /// A fresh signup on this install that hasn't seen it, unless the server
    /// switched the step off.
    static var isNeeded: Bool {
        guard ClientConfigService.shared.config.onboarding?.firstFavorite != false,
              let me = AuthService.shared.currentUser,
              let created = me.createdAt, Date().timeIntervalSince(created) < 48 * 3600 else { return false }
        return !UserDefaults.standard.bool(forKey: shownKey(me.id))
    }

    // MARK: - State

    private var results: [MKMapItem] = []
    private var savingKey: String?
    private var searchTimer: Timer?
    private var lastQuery = ""
    private var lastChip: String?
    private var origin: CLLocation?
    private var circles: [Circle] = []

    // MARK: - UI

    private let badgeView = GradientBadgeView(symbolName: "heart.fill")

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = FirstFavoriteCopy.headline
        label.font = .systemFont(ofSize: 26, weight: .bold)
        label.textColor = Constants.Colors.label
        label.numberOfLines = 0
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = FirstFavoriteCopy.subheadline
        label.font = .systemFont(ofSize: 15)
        label.textColor = Constants.Colors.secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private let searchContainer: UIView = {
        let view = UIView()
        view.backgroundColor = Constants.Colors.secondaryBackground
        view.layer.cornerRadius = 14
        return view
    }()

    private let searchField: UITextField = {
        let field = UITextField()
        field.placeholder = FirstFavoriteCopy.searchPlaceholder
        field.font = .systemFont(ofSize: 16)
        field.textColor = Constants.Colors.label
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private let chipsScrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        return scroll
    }()
    private let chipsStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// "Use my location" — asked here, where the reason is obvious
    private lazy var locationButton: UIButton = {
        let button = UIButton.smallActionButton(title: "📍 Use my location for places near me", style: .secondary)
        button.addTarget(self, action: #selector(useLocationTapped), for: .touchUpInside)
        return button
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = Constants.Colors.secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 2
        label.isHidden = true
        return label
    }()

    private let resultsTableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 68, bottom: 0, right: 16)
        tableView.rowHeight = 68
        tableView.keyboardDismissMode = .onDrag
        tableView.register(QuickStartResultCell.self, forCellReuseIdentifier: QuickStartResultCell.reuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    private lazy var skipButton: UIButton = {
        let button = UIButton.secondaryButton(title: "Skip for now")
        button.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Nothing to go back to: no empty bar over the question
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        navigationItem.hidesBackButton = true
        if let me = AuthService.shared.currentUser {
            UserDefaults.standard.set(true, forKey: Self.shownKey(me.id))
        }
        AnalyticsService.shared.logEvent("first_favorite_shown", parameters: [:])
        setupUI()
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
        resultsTableView.delegate = self
        resultsTableView.dataSource = self
        resolveOrigin()
        loadCircles()
    }

    private func setupUI() {
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)))
        icon.tintColor = Constants.Colors.secondaryLabel
        icon.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(icon)
        searchContainer.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchContainer.heightAnchor.constraint(equalToConstant: 48),
            icon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 14),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -12),
            searchField.topAnchor.constraint(equalTo: searchContainer.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor)
        ])

        for chip in FirstFavoriteCopy.chips {
            let button = UIButton.pillButton(title: chip.title)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
            button.layer.cornerRadius = 15
            button.accessibilityIdentifier = chip.query
            button.addAction(UIAction { [weak self] _ in self?.chipTapped(chip) }, for: .touchUpInside)
            chipsStack.addArrangedSubview(button)
        }
        chipsScrollView.addSubview(chipsStack)
        NSLayoutConstraint.activate([
            chipsScrollView.heightAnchor.constraint(equalToConstant: 32),
            chipsStack.topAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.topAnchor),
            chipsStack.bottomAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.bottomAnchor),
            chipsStack.leadingAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.leadingAnchor),
            chipsStack.trailingAnchor.constraint(equalTo: chipsScrollView.contentLayoutGuide.trailingAnchor),
            chipsStack.heightAnchor.constraint(equalTo: chipsScrollView.frameLayoutGuide.heightAnchor)
        ])

        badgeView.widthAnchor.constraint(equalToConstant: 56).isActive = true
        badgeView.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let badgeRow = UIStackView(arrangedSubviews: [badgeView, UIView()])
        badgeRow.axis = .horizontal

        let header = UIStackView(arrangedSubviews: [badgeRow, titleLabel, subtitleLabel, locationButton, searchContainer, chipsScrollView, statusLabel])
        header.axis = .vertical
        header.spacing = 12
        header.setCustomSpacing(6, after: titleLabel)
        header.setCustomSpacing(16, after: subtitleLabel)
        header.setCustomSpacing(10, after: searchContainer)
        header.translatesAutoresizingMaskIntoConstraints = false
        locationButton.isHidden = CLLocationManager().authorizationStatus != .notDetermined

        view.addSubview(header)
        view.addSubview(resultsTableView)
        view.addSubview(skipButton)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            resultsTableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            resultsTableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            resultsTableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            resultsTableView.bottomAnchor.constraint(equalTo: skipButton.topAnchor, constant: -8),
            skipButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            skipButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            skipButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        ])
    }

    // MARK: - Where to search

    /// A fix if we have one; then the zipcode or city they gave at signup;
    /// Charlotte (the app's default) only when there's nothing. Never
    /// prompts on its own.
    private func resolveOrigin() {
        if let cached = LocationService.shared.cachedLocation {
            origin = cached
            return
        }
        let status = CLLocationManager().authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            LocationService.shared.getCurrentLocation(timeout: 6) { [weak self] location in
                DispatchQueue.main.async { self?.originArrived(location) }
            }
        }
        geocodeSignupPlace()
    }

    /// Apple's geocoder (free) on the zipcode, or the "City, ST" signup saved
    private func geocodeSignupPlace() {
        let me = AuthService.shared.currentUser
        let text = [me?.zipcode, me?.location]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let text else { return }
        CLGeocoder().geocodeAddressString(text) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                // A real fix that landed meanwhile wins
                guard let self, self.origin == nil, let location = placemarks?.first?.location else { return }
                self.originArrived(location)
            }
        }
    }

    private var searchOrigin: CLLocation {
        origin ?? CLLocation(latitude: Constants.DefaultLocation.coordinate.latitude,
                             longitude: Constants.DefaultLocation.coordinate.longitude)
    }

    private func originArrived(_ location: CLLocation?) {
        guard let location else { return }
        let hadOrigin = origin != nil
        origin = location
        // Re-run what's on screen around the real spot
        if !hadOrigin, !lastQuery.isEmpty { performSearch(query: lastQuery) }
    }

    @objc private func useLocationTapped() {
        AnalyticsService.shared.logEvent("first_favorite_location_tapped", parameters: [:])
        LocationService.shared.requestAuthorization()
        locationButton.isEnabled = false
        locationButton.setTitle("Finding places near you…", for: .normal)
        waitForLocationAnswer(attempts: 0)
    }

    /// The permission alert answers asynchronously; check until it's answered
    private func waitForLocationAnswer(attempts: Int) {
        let status = CLLocationManager().authorizationStatus
        if status == .notDetermined, attempts < 60 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.waitForLocationAnswer(attempts: attempts + 1)
            }
            return
        }
        UIView.animate(withDuration: 0.25) { self.locationButton.isHidden = true }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        LocationService.shared.getCurrentLocation(timeout: 8) { [weak self] location in
            DispatchQueue.main.async { self?.originArrived(location) }
        }
    }

    private func loadCircles() {
        CircleService.shared.fetchUserCircles { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let circles) = result { self?.circles = circles }
            }
        }
    }

    // MARK: - Search

    @objc private func searchTextChanged() {
        let text = searchField.text ?? ""
        lastChip = nil
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.performSearch(query: text)
        }
    }

    private func chipTapped(_ chip: FirstFavoriteCopy.Chip) {
        AnalyticsService.shared.logEvent("first_favorite_chip", parameters: ["chip": chip.query])
        searchField.text = chip.query
        searchTimer?.invalidate()
        lastChip = chip.query
        performSearch(query: chip.query)
        searchField.resignFirstResponder()
    }

    private func performSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        lastQuery = trimmed
        guard trimmed.count >= 2 else {
            results = []
            resultsTableView.reloadData()
            setStatus(nil)
            return
        }
        setStatus("Searching near you…")
        let here = searchOrigin
        let region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        AppleMapsService.shared.searchPlaces(query: trimmed, region: region) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.lastQuery == trimmed else { return }
                switch result {
                case .success(let items):
                    // Nearest first: the place they love is usually close
                    self.results = items.sorted {
                        here.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude))
                            < here.distance(from: CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude))
                    }
                    self.setStatus(items.isEmpty ? "No places found for “\(trimmed)”. Try the full name." : nil)
                case .failure:
                    self.results = []
                    self.setStatus("Couldn't search right now. Check your connection and try again.")
                }
                self.resultsTableView.reloadData()
            }
        }
    }

    private func setStatus(_ text: String?) {
        statusLabel.text = text
        statusLabel.isHidden = text == nil
    }

    private func key(for item: MKMapItem) -> String {
        "\(item.name ?? "")|\(item.placemark.coordinate.latitude)|\(item.placemark.coordinate.longitude)"
    }

    // MARK: - Saving

    private func confirm(_ item: MKMapItem) {
        guard savingKey == nil else { return }
        searchField.resignFirstResponder()
        let name = item.name ?? "this place"
        AlertPresenter.showConfirmation(
            title: FirstFavoriteCopy.confirmTitle(placeName: name),
            message: item.placemark.title ?? "",
            confirmTitle: "Save it",
            cancelTitle: "Not this one",
            from: self,
            onConfirm: { [weak self] in self?.save(item) })
    }

    private func save(_ item: MKMapItem) {
        guard let circle = SystemCircles.first(.favoriteLocal, in: circles) ?? circles.first else {
            // Circles not loaded yet (or none): fetch, then try once more
            CircleService.shared.fetchUserCircles { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if case .success(let circles) = result, !circles.isEmpty {
                        self.circles = circles
                        self.save(item)
                    } else {
                        self.showError("Oops, something went wrong. Please try again.")
                    }
                }
            }
            return
        }
        let itemKey = key(for: item)
        savingKey = itemKey
        resultsTableView.reloadData()
        let details = AppleMapsService.shared.fetchPlaceDetails(mapItem: item)
        PlaceService.shared.createPlace(
            name: details.name,
            description: nil,
            address: details.address,
            category: details.category,
            circleId: circle.id,
            website: details.website,
            phone: details.phoneNumber,
            location: details.coordinate
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.savingKey = nil
                self.resultsTableView.reloadData()
                switch result {
                case .success(let place):
                    AnalyticsService.shared.logEvent("first_favorite_saved", parameters: [
                        "category": details.category.rawValue,
                        "had_location": self.origin != nil,
                        "from_chip": self.lastChip ?? "search"
                    ])
                    if let me = AuthService.shared.currentUser {
                        UserDefaults.standard.set(place.name, forKey: Self.savedNameKey(me.id))
                    }
                    NotificationCenter.default.post(name: .placeAdded, object: nil)
                    let result = FirstFavoriteResultViewController(place: place)
                    result.onContinue = { [weak self] in self?.complete(place.name) }
                    self.navigationController?.pushViewController(result, animated: true)
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    @objc private func skipTapped() {
        AnalyticsService.shared.logEvent("first_favorite_skipped", parameters: ["searched": !lastQuery.isEmpty])
        complete(nil)
    }

    private func complete(_ placeName: String?) {
        guard !didComplete else { return }
        didComplete = true
        let callback = onCompletion
        // From the presenter, so a celebration still up over this screen
        // (the Mapmaker badge) goes with it instead of eating the dismiss
        let host = navigationController ?? self
        if let presenter = host.presentingViewController {
            presenter.dismiss(animated: true) { callback?(placeName) }
        } else {
            callback?(placeName)
        }
    }
}

// MARK: - UITextFieldDelegate
extension FirstFavoriteViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        searchTimer?.invalidate()
        performSearch(query: textField.text ?? "")
        return true
    }
}

// MARK: - Results
extension FirstFavoriteViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: QuickStartResultCell.reuseId, for: indexPath) as! QuickStartResultCell
        guard indexPath.row < results.count else { return cell }
        let item = results[indexPath.row]
        let category = AppleMapItemFormFill.categoryMapping(poiCategory: item.pointOfInterestCategory, name: item.name).category
        cell.configure(name: item.name ?? "Unnamed place", address: item.placemark.title, category: category,
                       state: savingKey == key(for: item) ? .saving : .available)
        cell.setActionTitle("Love it")
        cell.onAdd = { [weak self] in self?.confirm(item) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < results.count else { return }
        confirm(results[indexPath.row])
    }
}
