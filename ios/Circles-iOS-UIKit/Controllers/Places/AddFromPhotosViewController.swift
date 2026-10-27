import UIKit
import CoreLocation

/// Add Place → "Add from photos" (Wes, 2026-10-17): one entry, three ways,
/// each explained; all end on the review page (PhotoPlacesReviewViewController).
final class AddFromPhotosViewController: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let savedPlaces: [Place]
    private let circles: [Circle]

    init(savedPlaces: [Place], circles: [Circle]) {
        self.savedPlaces = savedPlaces
        self.circles = circles
        super.init(nibName: nil, bundle: nil)
        title = "Add from photos"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        let intro = UILabel()
        intro.text = "We find the caf\u{00E9}s, restaurants, shops, hotels and other places in your photos. You review them before anything is saved."
        intro.font = .systemFont(ofSize: 15)
        intro.textColor = Constants.Colors.secondaryLabel
        intro.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [
            intro,
            OptionCard(symbol: "hand.tap.fill", title: "Pick photos",
                       detail: "Choose the exact photos. We find the place in each, and you pick the circle they go in.",
                       action: { [weak self] in self?.pickPhotos() }),
            OptionCard(symbol: "calendar", title: "Scan a time period",
                       detail: "A month or two you traveled, a whole year, or all your photos. The places go in a new circle.",
                       action: { [weak self] in self?.scanPeriod() }),
            OptionCard(symbol: "map.fill", title: "Build my map",
                       detail: "Places near you from all your photos, into \u{201C}Places from my photos.\u{201D} Your first 25 are free.",
                       action: { [weak self] in self?.buildMyMap() })
        ])
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(20, after: intro)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    // MARK: - The three ways

    private func pickPhotos() {
        AnalyticsService.shared.logEvent("add_from_photos", parameters: ["way": "pick"])
        PhotoPickerRelay.present(from: self, configuration: PhotoMetadataReader.pickerConfiguration(limit: 50)) { [weak self] results in
            guard let self else { return }
            let loading = AlertPresenter.showLoading(message: "Reading your photos\u{2026}", from: self)
            PhotoMetadataReader.load(results) { picked in
                loading.dismiss(animated: true) {
                    let (spots, unlocated) = PhotoFindSpot.fromPicked(picked)
                    guard !spots.isEmpty else {
                        return self.showError("These photos don\u{2019}t say where they were taken, so we can\u{2019}t find the places. (Location is off for the camera, or it was removed when shared.)")
                    }
                    if unlocated > 0 {
                        AlertPresenter.showBriefMessage("\(unlocated) photo\(unlocated == 1 ? " has" : "s have") no location and \(unlocated == 1 ? "was" : "were") skipped.", from: self, duration: 2.0)
                    }
                    self.review(spots, target: .photos, title: "Your photos")
                }
            }
        }
    }

    private func scanPeriod() {
        AnalyticsService.shared.logEvent("add_from_photos", parameters: ["way": "period"])
        withLibrary { [weak self] in
            guard let self else { return }
            let picker = PhotoScanPeriodViewController { [weak self] shots, name in
                guard let self else { return }
                // A trip circle keeps its places even when they're saved elsewhere
                let spots = PhotoFindSpot.fromLibrary(shots, saved: [], done: [], nearestTo: nil, nearestFirst: false)
                guard !spots.isEmpty else {
                    return self.showError("No places in those photos: they were taken at home, or without a location.")
                }
                self.review(spots, target: .new(name: name, privacy: .myNetwork, showOnMap: true), title: name)
            }
            self.navigationController?.pushViewController(picker, animated: true)
        }
    }

    private func buildMyMap() {
        AnalyticsService.shared.logEvent("add_from_photos", parameters: ["way": "map"])
        navigationController?.pushViewController(PhotoMapBuilderViewController(savedPlaces: savedPlaces, circles: circles), animated: true)
    }

    private func review(_ spots: [PhotoFindSpot], target: PhotoMapService.Target, title: String) {
        let finder = PhotoPlaceFinder(spots: spots)
        let review = PhotoPlacesReviewViewController(finder: finder, circles: circles, target: target, title: title)
        navigationController?.pushViewController(review, animated: true)
    }

    private func withLibrary(_ then: @escaping () -> Void) {
        PhotoLibraryIndex.shared.requestAccess { [weak self] granted in
            guard granted else {
                self?.showError("Allow FavCircles to see your photos in Settings to scan them. Or use Pick photos, which needs no access.")
                return
            }
            then()
        }
    }
}

/// A big tappable card: icon, title, one line of what it does.
private final class OptionCard: UIControl {
    private let action: () -> Void

    init(symbol: String, title: String, detail: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        backgroundColor = Constants.Colors.secondaryBackground
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = Constants.Colors.primary
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .systemFont(ofSize: 14)
        detailLabel.textColor = Constants.Colors.secondaryLabel
        detailLabel.numberOfLines = 0
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = Constants.Colors.secondaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let texts = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        texts.axis = .vertical
        texts.spacing = 4
        let row = UIStackView(arrangedSubviews: [icon, texts, chevron])
        row.alignment = .center
        row.spacing = 14
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
        isAccessibilityElement = true
        accessibilityLabel = "\(title). \(detail)"
        accessibilityTraits = .button
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }

    @objc private func tapped() { action() }
}

/// Scan a time period: trips we spotted, months, years, a range, or all.
final class PhotoScanPeriodViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private enum Section: Int, CaseIterable { case trips, months, years, other }

    private let onFind: ([PhotoLibraryMath.Shot], String) -> Void
    private var shots: [PhotoLibraryMath.Shot] = []
    private var trips: [(trip: PhotoLibraryMath.Trip, name: String?)] = []
    private var months: [(start: Date, count: Int)] = []
    private var years: [(year: Int, count: Int)] = []
    private var selected: Set<PhotoPeriod> = []
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private lazy var findButton = UIButton.primaryButton(title: "Find places")

    init(onFind: @escaping ([PhotoLibraryMath.Shot], String) -> Void) {
        self.onFind = onFind
        super.init(nibName: nil, bundle: nil)
        title = "Scan a time period"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        findButton.translatesAutoresizingMaskIntoConstraints = false
        findButton.addTarget(self, action: #selector(findTapped), for: .touchUpInside)
        view.addSubview(tableView)
        view.addSubview(findButton)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: findButton.topAnchor, constant: -8),
            findButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            findButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            findButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
        refreshButton()
        let loading = AlertPresenter.showLoading(message: "Reading your photos\u{2026}", from: self)
        PhotoLibraryIndex.shared.shots { [weak self] all in
            loading.dismiss(animated: true)
            guard let self else { return }
            self.shots = all
            let dates = all.map(\.date)
            self.months = PhotoPeriod.months(of: dates)
            self.years = PhotoPeriod.years(of: dates)
            if let home = PhotoLibraryMath.home(all.sorted { $0.date < $1.date }) {
                self.trips = PhotoLibraryMath.trips(all, home: home).prefix(8).map { ($0, nil) }
                self.nameTrips(from: 0)
            }
            self.tableView.reloadData()
        }
    }

    /// "Charleston", "Paris" for the trip rows, one lookup at a time
    private func nameTrips(from index: Int) {
        guard index < trips.count else { return }
        let center = trips[index].trip.center
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: center.latitude, longitude: center.longitude)) { [weak self] marks, _ in
            DispatchQueue.main.async {
                guard let self, index < self.trips.count else { return }
                self.trips[index].name = marks?.first?.locality ?? marks?.first?.administrativeArea
                self.tableView.reloadRows(at: [IndexPath(row: index, section: Section.trips.rawValue)], with: .none)
                self.nameTrips(from: index + 1)
            }
        }
    }

    private var selectedShots: [PhotoLibraryMath.Shot] {
        shots.filter { PhotoPeriod.contains(selected, $0.date) }
    }

    private func refreshButton() {
        let count = selected.isEmpty ? 0 : selectedShots.count
        findButton.setTitle(count == 0 ? "Pick a month, year or range" : "Find places in \(count) photo\(count == 1 ? "" : "s")", for: .normal)
        findButton.isEnabled = count > 0
        findButton.alpha = count > 0 ? 1 : 0.5
    }

    @objc private func findTapped() {
        let subset = selectedShots
        guard !subset.isEmpty else { return }
        // Name it after where most of these photos were
        let center = PhotoPlaceGrouper.median(subset.map(\.coordinate))
        let spread = center.map { c in subset.filter { PhotoLibraryMath.distance($0.coordinate, c) < 100_000 }.count * 3 >= subset.count * 2 } ?? false
        guard let center, spread else { return onFind(subset, PhotoPeriod.circleName(selected, place: nil)) }
        CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: center.latitude, longitude: center.longitude)) { [weak self] marks, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.onFind(subset, PhotoPeriod.circleName(self.selected, place: marks?.first?.locality))
            }
        }
    }

    // MARK: - Table

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .trips: return trips.isEmpty ? nil : "Trips in your photos"
        case .months: return "Months"
        case .years: return "Years"
        case .other: return "More"
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .trips: return trips.count
        case .months: return months.count
        case .years: return years.count
        case .other: return 2
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        let monthFormatter = DateFormatter()
        monthFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        switch Section(rawValue: indexPath.section)! {
        case .trips:
            let row = trips[indexPath.row]
            let range = PhotoPeriod.range(DateInterval(start: row.trip.start, end: row.trip.end.addingTimeInterval(86_400)))
            cell.textLabel?.text = PhotoLibraryMath.circleName(place: row.name, start: row.trip.start, end: row.trip.end)
            cell.detailTextLabel?.text = "\(row.trip.shots.count) photos"
            cell.accessoryType = selected.contains(range) ? .checkmark : .none
        case .months:
            let month = months[indexPath.row]
            cell.textLabel?.text = monthFormatter.string(from: month.start)
            cell.detailTextLabel?.text = "\(month.count)"
            cell.accessoryType = selected.contains(.month(month.start)) ? .checkmark : .none
        case .years:
            let year = years[indexPath.row]
            cell.textLabel?.text = String(year.year)
            cell.detailTextLabel?.text = "\(year.count)"
            cell.accessoryType = selected.contains(.year(year.year)) ? .checkmark : .none
        case .other:
            if indexPath.row == 0 {
                cell.textLabel?.text = "A date range\u{2026}"
                cell.accessoryType = selected.contains(where: { if case .range = $0 { return true } else { return false } }) ? .checkmark : .disclosureIndicator
            } else {
                cell.textLabel?.text = "All my photos"
                cell.detailTextLabel?.text = "\(shots.count)"
                cell.accessoryType = selected.contains(.all) ? .checkmark : .none
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let period: PhotoPeriod
        switch Section(rawValue: indexPath.section)! {
        case .trips:
            let trip = trips[indexPath.row].trip
            period = .range(DateInterval(start: trip.start, end: trip.end.addingTimeInterval(86_400)))
        case .months: period = .month(months[indexPath.row].start)
        case .years: period = .year(years[indexPath.row].year)
        case .other:
            if indexPath.row == 0 { return pickRange() }
            period = .all
        }
        if selected.contains(period) { selected.remove(period) } else { selected.insert(period) }
        if period == .all, selected.contains(.all) { selected = [.all] } else { selected.remove(.all) }
        tableView.reloadData()
        refreshButton()
    }

    private func pickRange() {
        let picker = PhotoDateRangeViewController { [weak self] start, end in
            guard let self else { return }
            self.selected.remove(.all)
            self.selected.insert(.range(DateInterval(start: start, end: max(start, end))))
            self.tableView.reloadData()
            self.refreshButton()
        }
        navigationController?.pushViewController(picker, animated: true)
    }
}

/// Two dates and Done.
final class PhotoDateRangeViewController: BaseViewController {
    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    private let onPick: (Date, Date) -> Void
    private let startPicker = UIDatePicker()
    private let endPicker = UIDatePicker()
    private lazy var doneButton = UIButton.primaryButton(title: "Use these dates")

    init(onPick: @escaping (Date, Date) -> Void) {
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
        title = "A date range"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.background
        let calendar = Calendar.current
        for picker in [startPicker, endPicker] {
            picker.datePickerMode = .date
            picker.preferredDatePickerStyle = .compact
            picker.maximumDate = Date()
        }
        startPicker.date = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        endPicker.date = Date()
        func row(_ title: String, _ picker: UIDatePicker) -> UIStackView {
            let label = UILabel()
            label.text = title
            label.font = .systemFont(ofSize: 17)
            let stack = UIStackView(arrangedSubviews: [label, UIView(), picker])
            stack.alignment = .center
            return stack
        }
        doneButton.addTarget(self, action: #selector(done), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [row("From", startPicker), row("Through", endPicker), doneButton])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
        ])
    }

    @objc private func done() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startPicker.date)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endPicker.date)) ?? endPicker.date
        onPick(start, end)
        navigationController?.popViewController(animated: true)
    }
}
