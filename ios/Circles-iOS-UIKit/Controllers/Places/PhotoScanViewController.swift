import UIKit
import Photos
import CoreLocation

/// "Build a circle from my photos" (Wes, 2026-10-09): pick a trip the app
/// found, a date range, or an album; the photos' stops become a new circle
/// after a review. Everything is read on the phone.
final class PhotoScanViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate {

    private struct TripRow {
        let trip: PhotoLibraryMath.Trip
        var name: String?
    }

    private enum Section: Int, CaseIterable { case trips, dates, albums }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var shots: [PhotoLibraryMath.Shot] = []
    private var home: CLLocationCoordinate2D?
    private var trips: [TripRow] = []
    private var albums: [(title: String, collection: PHAssetCollection)] = []
    private let savedPlaces: [Place]
    private let circles: [Circle]
    private let geocoder = CLGeocoder()

    override var showsLoadingIndicator: Bool { true }

    init(savedPlaces: [Place], circles: [Circle]) {
        self.savedPlaces = savedPlaces
        self.circles = circles
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Circle from photos"
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func loadData(completion: (() -> Void)? = nil) {
        PhotoLibraryIndex.shared.requestAccess { [weak self] granted in
            guard let self else { return }
            guard granted else {
                completion?()
                self.showEmptyState(message: "FavCircles needs access to your photos to find the places in them.\n\nTurn it on in Settings → FavCircles → Photos.")
                return
            }
            PhotoLibraryIndex.shared.shots { [weak self] all in
                guard let self else { return }
                self.shots = all
                self.home = PhotoLibraryMath.home(all)
                self.trips = self.home.map { home in PhotoLibraryMath.trips(all, home: home).prefix(12).map { TripRow(trip: $0) } } ?? []
                self.albums = PhotoLibraryIndex.shared.albums()
                self.tableView.reloadData()
                completion?()
                self.nameTrips()
            }
        }
    }

    /// "Charleston" for each trip, one lookup at a time (Apple limits them)
    private func nameTrips(from index: Int = 0) {
        guard index < trips.count else { return }
        let c = trips[index].trip.center
        geocoder.reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)) { [weak self] marks, _ in
            DispatchQueue.main.async {
                guard let self, index < self.trips.count else { return }
                self.trips[index].name = marks?.first?.locality ?? marks?.first?.administrativeArea
                self.tableView.reloadRows(at: [IndexPath(row: index, section: Section.trips.rawValue)], with: .none)
                self.nameTrips(from: index + 1)
            }
        }
    }

    // MARK: - Table

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .trips: return max(trips.count, 1)
        case .dates: return 1
        case .albums: return min(albums.count, 40)
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .trips: return "Your trips"
        case .dates: return "Pick the dates"
        case .albums: return albums.isEmpty ? nil : "From an album"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        Section(rawValue: section) == .trips
            ? "Days your photos were taken far from home. Your photos stay on your phone; only the ones you add to places are uploaded."
            : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.accessoryType = .disclosureIndicator
        switch Section(rawValue: indexPath.section)! {
        case .trips:
            guard trips.indices.contains(indexPath.row) else {
                cell.textLabel?.text = "No trips found yet"
                cell.detailTextLabel?.text = "Pick dates or an album instead."
                cell.accessoryType = .none
                cell.selectionStyle = .none
                return cell
            }
            let row = trips[indexPath.row]
            cell.textLabel?.text = row.name ?? "Trip"
            cell.detailTextLabel?.text = "\(Self.days(row.trip.start, row.trip.end)) · \(row.trip.shots.count) photos"
            cell.imageView?.image = UIImage(systemName: "suitcase.rolling")
        case .dates:
            cell.textLabel?.text = "Choose dates…"
            cell.imageView?.image = UIImage(systemName: "calendar")
        case .albums:
            cell.textLabel?.text = albums[indexPath.row].title
            cell.imageView?.image = UIImage(systemName: "rectangle.stack")
        }
        cell.detailTextLabel?.textColor = .secondaryLabel
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .trips:
            guard trips.indices.contains(indexPath.row) else { return }
            let row = trips[indexPath.row]
            review(row.trip.shots, name: PhotoLibraryMath.circleName(place: row.name, start: row.trip.start, end: row.trip.end))
        case .dates:
            pickDates()
        case .albums:
            let album = albums[indexPath.row]
            PhotoLibraryIndex.shared.shots(in: album.collection) { [weak self] albumShots in
                self?.review(albumShots, name: album.title)
            }
        }
    }

    private func pickDates() {
        let picker = PhotoScanDatesViewController { [weak self] start, end in
            guard let self else { return }
            let inRange = self.shots.filter { $0.date >= start && $0.date < end }
            self.review(inRange, name: PhotoLibraryMath.circleName(place: nil, start: start, end: end.addingTimeInterval(-1)))
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    /// The stops in these photos, minus home and places already saved
    private func review(_ subset: [PhotoLibraryMath.Shot], name: String) {
        let saved = savedPlaces.compactMap { $0.location?.clLocation?.coordinate }
        let spots = PhotoLibraryMath.spots(subset).filter { !PhotoLibraryMath.isSkippable($0, home: home, saved: saved) }
        guard !spots.isEmpty else {
            showError("No new places in those photos — they were taken at home, at places you've already saved, or without a location.")
            return
        }
        // The most-photographed stops when there are a lot (Apple Maps lookups are limited)
        let capped = spots.count > PhotoScanReviewViewController.maxSpots
            ? Array(spots.sorted { $0.shots.count > $1.shots.count }.prefix(PhotoScanReviewViewController.maxSpots)).sorted { $0.start < $1.start }
            : spots
        navigationController?.pushViewController(PhotoScanReviewViewController(spots: capped, suggestedName: name), animated: true)
    }

    private static func days(_ start: Date, _ end: Date) -> String {
        let f = DateIntervalFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: start, to: end)
    }
}

/// Two dates and a Find button.
final class PhotoScanDatesViewController: BaseViewController {
    private let onPick: (Date, Date) -> Void
    private let startPicker = UIDatePicker()
    private let endPicker = UIDatePicker()
    private lazy var findButton = UIButton.primaryButton(title: "Find places")

    override var loadsDataOnViewDidLoad: Bool { false }
    override var showsLoadingIndicator: Bool { false }

    init(onPick: @escaping (Date, Date) -> Void) {
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Pick the dates"
        view.backgroundColor = .systemGroupedBackground
        let calendar = Calendar.current
        startPicker.date = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        endPicker.date = Date()
        [startPicker, endPicker].forEach { $0.datePickerMode = .date; $0.preferredDatePickerStyle = .compact; $0.maximumDate = Date() }
        func row(_ title: String, _ picker: UIDatePicker) -> UIStackView {
            let label = UILabel()
            label.text = title
            label.font = .systemFont(ofSize: 17, weight: .medium)
            let stack = UIStackView(arrangedSubviews: [label, picker])
            stack.distribution = .equalSpacing
            return stack
        }
        let stack = UIStackView(arrangedSubviews: [row("From", startPicker), row("Through", endPicker), findButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        findButton.addTarget(self, action: #selector(findTapped), for: .touchUpInside)
    }

    @objc private func findTapped() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(startPicker.date, endPicker.date))
        let endDay = calendar.startOfDay(for: max(startPicker.date, endPicker.date))
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        onPick(start, end)
    }
}
