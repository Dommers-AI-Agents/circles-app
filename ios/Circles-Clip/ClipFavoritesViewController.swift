import CoreLocation
import MapKit
import UIKit

/// Step 2: a few first favorites (2026-11-24). Apple's points of interest
/// around the store (or the zip they typed) as chips, a search box for the
/// rest, up to three picks, saved together through POST clip/favorites (the
/// core save, into Favorite Local Spots). MapKit is a system framework, so
/// the clip stays small, and no location prompt is needed.
final class ClipFavoritesViewController: ClipStepViewController, UITextFieldDelegate {
    private let searchField = ClipTheme.field(placeholder: "Search a place you love", contentType: .location)
    private let listCaption: UILabel
    private let statusLabel = ClipTheme.label(.systemFont(ofSize: 14), color: UIColor.white.withAlphaComponent(0.75))
    private let chipRows = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)

    private let origin: CLLocationCoordinate2D
    private var nearby: [ClipPlacePick] = []
    private var results: [ClipPlacePick] = []
    private var shown: [ClipPlacePick] = []
    private var picks: [ClipPlacePick] = []
    private var chips: [UIButton] = []
    private var searchTimer: Timer?
    private var lastQuery = ""
    private var saving = false

    static let maxPicks = 3
    /// The kinds of places people love most (the app's first-favorite screen uses the same list)
    private static let nearbyCategories: [MKPointOfInterestCategory] = [
        .cafe, .restaurant, .bakery, .brewery, .winery, .nightlife, .park, .fitnessCenter, .foodMarket, .museum
    ]

    init(flow: ClipOnboardingFlow) {
        // The flow only offers this step with an origin
        origin = flow.origin ?? CLLocationCoordinate2D(latitude: 35.2271, longitude: -80.8431)
        listCaption = ClipTheme.label(.systemFont(ofSize: 13, weight: .bold), color: ClipTheme.gold)
        super.init(flow: flow, step: .favorites, primary: "Add to my map")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        hookLabel.attributedText = ClipTheme.hookText("Your first", "favorites.", size: 44)
        detailLabel.text = flow.store.map { "Pick up to three places you love nearby. They go on your map right now, next to \($0.name)." }
            ?? "Pick up to three places you love nearby. They go on your map right now."

        searchField.delegate = self
        searchField.returnKeyType = .search
        searchField.autocorrectionType = .no
        searchField.clearButtonMode = .whileEditing
        searchField.accessibilityIdentifier = "clipPlaceSearch"
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        listCaption.text = "NEAR YOU"
        ClipTheme.lift(listCaption)
        ClipTheme.lift(statusLabel)
        chipRows.axis = .vertical
        chipRows.spacing = 8
        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.startAnimating()
        statusLabel.text = "Finding places near you…"

        [searchField, listCaption, spinner, statusLabel, chipRows, errorLabel].forEach { stack.addArrangedSubview($0) }
        stack.setCustomSpacing(16, after: searchField)
        stack.setCustomSpacing(8, after: listCaption)
        setPrimaryEnabled(false)
        ClipTheme.animateIn([stepLabel, hookLabel, detailLabel, searchField, listCaption, primaryButton])
        loadNearby(radius: 3_000)
    }

    // MARK: - Nearby

    /// Apple's points of interest around the origin, nearest first; wider
    /// when the first ring is thin, then a plain "Restaurant" search
    private func loadNearby(radius: CLLocationDistance) {
        let request = MKLocalPointsOfInterestRequest(center: origin, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: Self.nearbyCategories)
        Task { @MainActor in
            let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
            let picks = self.picks(from: items)
            if picks.count < 5, radius < 27_000 {
                if !picks.isEmpty { self.showNearby(picks) }
                self.loadNearby(radius: radius * 3)
            } else if picks.isEmpty {
                self.loadNearbyFallback()
            } else {
                self.showNearby(picks)
            }
        }
    }

    private func loadNearbyFallback() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "Restaurant"
        request.region = MKCoordinateRegion(center: origin, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        request.resultTypes = .pointOfInterest
        Task { @MainActor in
            let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
            let picks = self.picks(from: items)
            if picks.isEmpty {
                self.spinner.stopAnimating()
                self.statusLabel.text = "Nothing close by yet. Search for a place you love."
            } else {
                self.showNearby(picks)
            }
        }
    }

    /// Picks from map items: nearest first, the store itself left out, no repeats
    private func picks(from items: [MKMapItem]) -> [ClipPlacePick] {
        let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let storeName = flow.store?.name.lowercased()
        var seen = Set<String>()
        return items
            .compactMap(ClipPlacePick.init)
            .filter { $0.name.lowercased() != storeName }
            .filter { seen.insert($0.key).inserted }
            .sorted {
                here.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))
                    < here.distance(from: CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude))
            }
    }

    private func showNearby(_ picks: [ClipPlacePick]) {
        nearby = Array(picks.prefix(8))
        if lastQuery.count < 2 { showList(nearby, caption: "NEAR YOU") }
    }

    // MARK: - Search

    @objc private func searchChanged() {
        searchTimer?.invalidate()
        let text = searchField.text ?? ""
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.search(text)
        }
    }

    private func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        lastQuery = trimmed
        guard trimmed.count >= 2 else {
            showList(nearby, caption: "NEAR YOU")
            return
        }
        spinner.startAnimating()
        statusLabel.text = "Searching near you…"
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = MKCoordinateRegion(center: origin, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        request.resultTypes = .pointOfInterest
        Task { @MainActor in
            let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
            guard self.lastQuery == trimmed else { return }
            self.results = Array(self.picks(from: items).prefix(8))
            if self.results.isEmpty {
                self.spinner.stopAnimating()
                self.statusLabel.text = "Nothing for \"\(trimmed)\" near you. Try another name."
                self.statusLabel.isHidden = false
                self.clearChips()
            } else {
                self.showList(self.results, caption: "RESULTS")
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        searchTimer?.invalidate()
        search(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }

    // MARK: - Chips

    private func clearChips() {
        chipRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        chips = []
        shown = []
    }

    /// Chips packed into rows that fit the screen; picks stay gold
    private func showList(_ list: [ClipPlacePick], caption: String) {
        spinner.stopAnimating()
        statusLabel.isHidden = true
        listCaption.text = caption
        clearChips()
        shown = list
        let available = (view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width) - 52
        var rows: [UIStackView] = []
        var width: CGFloat = 0
        for (index, place) in list.enumerated() {
            let chip = Self.chip(place.name, selected: picks.contains(place))
            chip.tag = index
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            chips.append(chip)
            let w = chip.intrinsicContentSize.width
            if rows.isEmpty || width + w + 8 > available {
                let row = UIStackView()
                row.axis = .horizontal
                row.spacing = 8
                row.alignment = .center
                rows.append(row)
                width = 0
            }
            rows.last?.addArrangedSubview(chip)
            width += w + 8
        }
        for row in rows {
            row.addArrangedSubview(UIView()) // left-aligned
            chipRows.addArrangedSubview(row)
        }
        ClipTheme.animateIn(rows, baseDelay: 0)
        #if DEBUG
        ClipAutopilot.shared?.ready(self)
        #endif
    }

    private static func chip(_ title: String, selected: Bool) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.background.strokeColor = UIColor.white.withAlphaComponent(0.4)
        config.background.strokeWidth = 1
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]))
        config.imagePadding = 6
        config.titleLineBreakMode = .byTruncatingTail
        let button = UIButton(configuration: config)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.titleLabel?.numberOfLines = 2
        style(button, selected: selected)
        return button
    }

    private static func style(_ button: UIButton, selected: Bool) {
        button.configuration?.baseBackgroundColor = selected ? ClipTheme.gold : UIColor.white.withAlphaComponent(0.16)
        button.configuration?.baseForegroundColor = selected ? ClipTheme.ink : .white
        button.configuration?.image = selected
            ? UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
            : nil
    }

    @objc private func chipTapped(_ chip: UIButton) {
        guard chip.tag < shown.count, !saving else { return }
        let place = shown[chip.tag]
        hideError()
        if let at = picks.firstIndex(of: place) {
            picks.remove(at: at)
        } else if picks.count < Self.maxPicks {
            picks.append(place)
        } else {
            showError("Three is plenty for now. You can add more in the app.")
            return
        }
        Self.style(chip, selected: picks.contains(place))
        UISelectionFeedbackGenerator().selectionChanged()
        setPrimaryEnabled(!picks.isEmpty)
        setPrimaryTitle(picks.isEmpty ? "Add to my map" : "Add \(picks.count) place\(picks.count == 1 ? "" : "s") to my map")
    }

    // MARK: - Save

    override func primaryTapped() {
        guard !picks.isEmpty, !saving else { return }
        saving = true
        hideError()
        view.endEditing(true)
        setPrimaryBusy(true)
        let bodies = picks.map(\.body)
        Task { @MainActor in
            do {
                let result = try await ClipAPIClient.shared.saveFavorites(bodies, bearer: flow.session.token)
                let onMap = result.saved.count + result.alreadySaved.count
                guard onMap > 0 else {
                    saving = false
                    setPrimaryBusy(false)
                    setPrimaryEnabled(true)
                    showError("Couldn't save those just now. You can add them in the app.")
                    return
                }
                flow.record { s in
                    s.favoritesSaved += result.saved.count
                    s.favoriteNames += result.saved.map(\.name)
                }
                flow.complete(.favorites)
                var line = "\(onMap) place\(onMap == 1 ? "" : "s") on your map"
                if let coins = result.coins, coins > 0 { line += " · +\(coins) FavCoins" }
                toast(line)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                setPrimaryBusy(false)
                setPrimaryEnabled(false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { [weak self] in self?.advance() }
            } catch ClipAPIError.unauthorized {
                saving = false
                setPrimaryBusy(false)
                setPrimaryEnabled(true)
                showError("Please sign in again.")
            } catch {
                saving = false
                setPrimaryBusy(false)
                setPrimaryEnabled(true)
                showError(error.localizedDescription)
            }
        }
    }

    #if DEBUG
    /// The autopilot's picks: the first two chips, then the button
    func autopilotPick() {
        guard picks.isEmpty, chips.count >= 1 else { return }
        for chip in chips.prefix(2) { chipTapped(chip) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.primaryTapped() }
    }
    #endif
}
