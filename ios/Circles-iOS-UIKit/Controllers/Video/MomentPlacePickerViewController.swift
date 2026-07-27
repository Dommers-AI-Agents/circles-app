import UIKit
import MapKit
import CoreLocation

protocol MomentPlacePickerDelegate: AnyObject {
    /// The user picked a place and a visibility for the moment.
    func momentPlacePicker(_ picker: MomentPlacePickerViewController,
                           didSelect place: Place,
                           visibility: VideoVisibility)
}

/// Place picker for posting a Moment — same shape as the check-in place
/// selection (My Places sorted by distance / Nearby), with a bubble privacy
/// selector on top so the audience is obvious and adjustable.
class MomentPlacePickerViewController: BaseViewController {

    override var loadsDataOnViewDidLoad: Bool { false }

    weak var delegate: MomentPlacePickerDelegate?
    private var visibility: VideoVisibility

    private var currentLocation: CLLocation?
    private var myPlaces: [Place] = []      // full distance-sorted list
    private var nearbyPlaces: [Place] = []  // network places nearby (not mine)
    private var myPlacesQuery = ""          // search filter for My Places
    private var nearbyQuery = ""            // search filter for Nearby
    private var isLoading = false

    init(initialVisibility: VideoVisibility) {
        self.visibility = initialVisibility
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UI

    private let privacyLabel: UILabel = {
        let l = UILabel()
        l.text = "Who can see this?"
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = Constants.Colors.secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private lazy var privacyControl: UISegmentedControl = {
        let c = UISegmentedControl(items: VideoVisibility.allCases.map { $0.displayLabel })
        c.selectedSegmentIndex = VideoVisibility.allCases.firstIndex(of: visibility) ?? 0
        c.addTarget(self, action: #selector(privacyChanged), for: .valueChanged)
        c.translatesAutoresizingMaskIntoConstraints = false
        return c
    }()
    private let privacySubtitle: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12)
        l.textColor = Constants.Colors.secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let sourceControl: UISegmentedControl = {
        let c = UISegmentedControl(items: ["My Places", "Nearby"])
        c.selectedSegmentIndex = 0
        c.translatesAutoresizingMaskIntoConstraints = false
        return c
    }()
    private let searchBar: UISearchBar = {
        let s = UISearchBar()
        s.placeholder = "Search places..."
        s.searchBarStyle = .minimal
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()
    private let tableView: UITableView = {
        let t = UITableView()
        t.backgroundColor = Constants.Colors.background
        t.translatesAutoresizingMaskIntoConstraints = false
        return t
    }()
    private let loadingIndicator: UIActivityIndicatorView = {
        let i = UIActivityIndicatorView(style: .medium)
        i.hidesWhenStopped = true
        i.translatesAutoresizingMaskIntoConstraints = false
        return i
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tag a place"
        view.backgroundColor = Constants.Colors.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

        sourceControl.addTarget(self, action: #selector(sourceChanged), for: .valueChanged)
        searchBar.delegate = self
        tableView.delegate = self
        tableView.dataSource = self

        [privacyLabel, privacyControl, privacySubtitle, sourceControl, searchBar, tableView, loadingIndicator].forEach { view.addSubview($0) }
        setupConstraints()
        updatePrivacySubtitle()

        // Load My Places right away (sorts alphabetically until we have a
        // location), then re-sort by distance and load the active tab once the
        // location resolves.
        loadMyPlaces()
        LocationService.shared.getCurrentLocation { [weak self] location in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.currentLocation = location
                self.myPlaces = self.sortByDistance(self.myPlaces)
                if self.isMyPlaces { self.tableView.reloadData() } else { self.loadNearby() }
            }
        }
    }

    private func setupConstraints() {
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            privacyLabel.topAnchor.constraint(equalTo: g.topAnchor, constant: 12),
            privacyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            privacyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            privacyControl.topAnchor.constraint(equalTo: privacyLabel.bottomAnchor, constant: 8),
            privacyControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            privacyControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            privacySubtitle.topAnchor.constraint(equalTo: privacyControl.bottomAnchor, constant: 6),
            privacySubtitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            privacySubtitle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            sourceControl.topAnchor.constraint(equalTo: privacySubtitle.bottomAnchor, constant: 16),
            sourceControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            sourceControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            searchBar.topAnchor.constraint(equalTo: sourceControl.bottomAnchor, constant: 8),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.topAnchor.constraint(equalTo: tableView.topAnchor, constant: 40)
        ])
    }

    // MARK: - Privacy bubble

    @objc private func privacyChanged() {
        visibility = VideoVisibility.allCases[privacyControl.selectedSegmentIndex]
        updatePrivacySubtitle()
    }
    private func updatePrivacySubtitle() {
        privacySubtitle.text = visibility.pickerSubtitle
    }

    // MARK: - Source (My Places / Nearby)

    @objc private func sourceChanged() {
        searchBar.text = ""
        myPlacesQuery = ""
        nearbyQuery = ""
        if isMyPlaces {
            tableView.reloadData()
        } else if nearbyPlaces.isEmpty {
            loadNearby()
        } else {
            tableView.reloadData()
        }
    }

    private var isMyPlaces: Bool { sourceControl.selectedSegmentIndex == 0 }
    private var rows: [Place] {
        let source = isMyPlaces ? myPlaces : nearbyPlaces
        let query = isMyPlaces ? myPlacesQuery : nearbyQuery
        guard !query.isEmpty else { return source }
        return source.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.address.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Data

    private func loadMyPlaces() {
        setLoading(true)
        PlaceService.shared.getMyPlacesForCheckIn { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setLoading(false)
                if case .success(let places) = result {
                    self.myPlaces = self.sortByDistance(places)
                }
                if self.isMyPlaces { self.tableView.reloadData() }
            }
        }
    }

    private func sortByDistance(_ places: [Place]) -> [Place] {
        guard let loc = currentLocation else { return places.sorted { $0.name < $1.name } }
        return places.sorted { a, b in
            let da = distance(to: a, from: loc)
            let db = distance(to: b, from: loc)
            if let da = da, let db = db { return da < db }
            if da != nil { return true }
            if db != nil { return false }
            return a.name < b.name
        }
    }

    private func distance(to place: Place, from loc: CLLocation) -> CLLocationDistance? {
        guard let lat = place.latitude, let lng = place.longitude else { return nil }
        return loc.distance(from: CLLocation(latitude: lat, longitude: lng))
    }

    /// Nearby = all network places near the user (not the user's own),
    /// distance-sorted. Shared with check-in via PlaceService.getNearbyPlaces.
    private func loadNearby() {
        guard let loc = currentLocation else {
            nearbyPlaces = []
            tableView.reloadData()
            return
        }
        setLoading(true)
        PlaceService.shared.getNearbyPlaces(near: loc) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setLoading(false)
                if case .success(let places) = result {
                    self.nearbyPlaces = places
                }
                if !self.isMyPlaces { self.tableView.reloadData() }
            }
        }
    }

    private func setLoading(_ loading: Bool) {
        isLoading = loading
        loading ? loadingIndicator.startAnimating() : loadingIndicator.stopAnimating()
    }

    @objc private func cancelTapped() { dismiss(animated: true) }
}

// MARK: - Table

extension MomentPlacePickerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlaceCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "PlaceCell")
        let place = rows[indexPath.row]
        cell.textLabel?.text = place.name

        var detail: [String] = []
        if let loc = currentLocation, let d = distance(to: place, from: loc) {
            let f = MKDistanceFormatter(); f.unitStyle = .abbreviated
            detail.append(f.string(fromDistance: d))
        }
        if isMyPlaces, let circleName = place.circleName { detail.append(circleName) }
        if !place.address.isEmpty { detail.append(place.address) }
        cell.detailTextLabel?.text = detail.joined(separator: " • ")
        cell.detailTextLabel?.textColor = Constants.Colors.secondaryLabel
        cell.imageView?.image = UIImage(systemName: "mappin.circle.fill")
        cell.imageView?.tintColor = Constants.Colors.primary
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let place = rows[indexPath.row]
        delegate?.momentPlacePicker(self, didSelect: place, visibility: visibility)
    }
}

// MARK: - Search

extension MomentPlacePickerViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        // Both tabs filter their already-loaded, distance-sorted list locally
        if isMyPlaces {
            myPlacesQuery = q
        } else {
            nearbyQuery = q
        }
        tableView.reloadData()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
