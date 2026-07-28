import UIKit
import MapKit

/// Map pin that carries its venue's category so the marker can show the right
/// color + glyph (matching the rest of the app's category pins).
final class VenueAnnotation: MKPointAnnotation {
    let category: PlaceCategory
    init(category: PlaceCategory) {
        self.category = category
        super.init()
    }
}

/// Third level of the location lens: every venue in a city, drawn from ALL of
/// the user's circles, each labeled with its source circle(s). A map header
/// shows the pins; a category chip bar filters the list across circles, and the
/// densest neighborhood is surfaced for the active filter.
final class CityPlacesViewController: BaseTableViewController {

    private let cityKey: String
    private let titleText: String
    private var allVenues: [CityVenue] = []
    private var selectedGroup: PlaceCategoryGroup = .all

    private let mapView: MKMapView = {
        let m = MKMapView()
        m.isRotateEnabled = false
        m.isPitchEnabled = false
        m.autoresizingMask = [.flexibleWidth]
        return m
    }()
    private let chipBar: CategoryChipBar = {
        let bar = CategoryChipBar()
        bar.autoresizingMask = [.flexibleWidth]
        return bar
    }()

    private let mapHeight: CGFloat = 200
    private let chipsHeight: CGFloat = 52

    override var emptyStateMessage: String? { "No places here yet." }

    init(cityKey: String, titleText: String) {
        self.cityKey = cityKey
        self.titleText = titleText
        super.init(style: .plain)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = titleText
        tableView.register(CityVenueCell.self, forCellReuseIdentifier: CityVenueCell.reuseId)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        mapView.delegate = self
        chipBar.onSelect = { [weak self] group in self?.applyFilter(group) }
        setupHeader()
    }

    private func setupHeader() {
        let width = view.bounds.width
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: mapHeight + chipsHeight))
        container.autoresizingMask = [.flexibleWidth]
        mapView.frame = CGRect(x: 0, y: 0, width: width, height: mapHeight)
        chipBar.frame = CGRect(x: 0, y: mapHeight, width: width, height: chipsHeight)
        container.addSubview(mapView)
        container.addSubview(chipBar)
        tableView.tableHeaderView = container
    }

    // MARK: - Data

    private var filteredVenues: [CityVenue] {
        selectedGroup == .all ? allVenues : allVenues.filter { selectedGroup.matches($0.category) }
    }

    override func loadData(completion: (() -> Void)? = nil) {
        BrowseService.shared.getCityPlaces(cityKey: cityKey) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { completion?(); return }
                switch result {
                case .success(let resp):
                    self.allVenues = resp.places
                    self.chipBar.setGroups(
                        PlaceCategoryGroup.present(in: self.allVenues.map { $0.category }),
                        selected: .all
                    )
                    self.refresh()
                    if self.allVenues.isEmpty { self.showEmptyState() }
                case .failure(let error):
                    self.showError(error)
                }
                completion?()
            }
        }
    }

    private func applyFilter(_ group: PlaceCategoryGroup) {
        selectedGroup = group
        refresh()
    }

    /// Re-render the list, map, and header stat for the active filter.
    private func refresh() {
        tableView.reloadData()
        updateMap()
        updateHeaderStat()
    }

    private func updateHeaderStat() {
        let venues = filteredVenues
        let noun = selectedGroup == .all
            ? (venues.count == 1 ? "pin" : "pins")
            : selectedGroup.title.lowercased()
        var text = "\(venues.count) \(noun)"
        if let hood = densestNeighborhood(in: venues) {
            text += " · Most in \(hood)"
        }
        navigationItem.prompt = text
    }

    /// The neighborhood holding the most pins for the current filter, shown only
    /// when it's meaningful (≥2 pins share it). Falls back to nothing (→ city).
    private func densestNeighborhood(in venues: [CityVenue]) -> String? {
        var counts: [String: Int] = [:]
        for v in venues {
            guard let n = v.neighborhood, !n.isEmpty else { continue }
            counts[n, default: 0] += 1
        }
        guard let top = counts.max(by: { $0.value < $1.value }), top.value >= 2 else { return nil }
        return top.key
    }

    private func updateMap() {
        mapView.removeAnnotations(mapView.annotations)
        let annotations: [VenueAnnotation] = filteredVenues.compactMap { venue in
            guard let coord = venue.coordinate else { return nil }
            let a = VenueAnnotation(category: PlaceCategory(rawValue: venue.category) ?? .other)
            a.coordinate = coord
            a.title = venue.name
            a.subtitle = venue.subtitle
            return a
        }
        mapView.addAnnotations(annotations)
        if !annotations.isEmpty { mapView.showAnnotations(annotations, animated: false) }
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredVenues.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CityVenueCell.reuseId, for: indexPath) as! CityVenueCell
        cell.configure(with: filteredVenues[indexPath.row])
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // v1: focus the pin on the map. (Full pin-detail card is Part 4.)
        let venue = filteredVenues[indexPath.row]
        guard let coord = venue.coordinate else { return }
        let region = MKCoordinateRegion(center: coord, latitudinalMeters: 800, longitudinalMeters: 800)
        mapView.setRegion(region, animated: true)
        if let match = mapView.annotations.first(where: {
            $0.coordinate.latitude == coord.latitude && $0.coordinate.longitude == coord.longitude
        }) {
            mapView.selectAnnotation(match, animated: true)
        }
        tableView.scrollRectToVisible(mapView.frame, animated: true)
    }
}

extension CityPlacesViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !(annotation is MKUserLocation) else { return nil }
        let id = "venuePin"
        let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
        view.annotation = annotation
        view.canShowCallout = true
        if let venue = annotation as? VenueAnnotation {
            view.markerTintColor = venue.category.color
            view.glyphImage = UIImage(systemName: venue.category.systemIconName)
        } else {
            view.markerTintColor = Constants.Colors.primary
        }
        return view
    }
}
