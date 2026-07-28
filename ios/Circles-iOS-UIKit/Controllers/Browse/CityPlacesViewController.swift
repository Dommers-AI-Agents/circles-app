import UIKit
import MapKit

/// Third level of the location lens: every venue in a city, drawn from ALL of
/// the user's circles, each labeled with its source circle(s). A map header
/// shows the pins. This is the core "aggregate a city across circles" behavior.
final class CityPlacesViewController: BaseTableViewController {

    private let cityKey: String
    private let titleText: String
    private var venues: [CityVenue] = []
    private var topNeighborhood: TopNeighborhood?

    private let mapView: MKMapView = {
        let m = MKMapView()
        m.isRotateEnabled = false
        m.isPitchEnabled = false
        return m
    }()

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
        setupMapHeader()
    }

    private func setupMapHeader() {
        mapView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 200)
        tableView.tableHeaderView = mapView
    }

    override func loadData(completion: (() -> Void)? = nil) {
        BrowseService.shared.getCityPlaces(cityKey: cityKey) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { completion?(); return }
                switch result {
                case .success(let resp):
                    self.venues = resp.places
                    self.topNeighborhood = resp.topNeighborhood
                    self.tableView.reloadData()
                    self.updateMap()
                    self.updateHeaderTitle(count: resp.count)
                    if self.venues.isEmpty { self.showEmptyState() }
                case .failure(let error):
                    self.showError(error)
                }
                completion?()
            }
        }
    }

    private func updateHeaderTitle(count: Int) {
        // "40 pins" — and, when we have neighborhood data, the densest one.
        var text = "\(count) \(count == 1 ? "pin" : "pins")"
        if let top = topNeighborhood {
            text += " · Most in \(top.neighborhood)"
        }
        navigationItem.prompt = text
    }

    private func updateMap() {
        mapView.removeAnnotations(mapView.annotations)
        var annotations: [MKPointAnnotation] = []
        for venue in venues {
            guard let coord = venue.coordinate else { continue }
            let a = MKPointAnnotation()
            a.coordinate = coord
            a.title = venue.name
            a.subtitle = venue.subtitle
            annotations.append(a)
        }
        mapView.addAnnotations(annotations)
        if !annotations.isEmpty {
            mapView.showAnnotations(annotations, animated: false)
        }
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        venues.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CityVenueCell.reuseId, for: indexPath) as! CityVenueCell
        cell.configure(with: venues[indexPath.row])
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        // v1: focus the pin on the map. (Full pin-detail card is Part 4.)
        let venue = venues[indexPath.row]
        guard let coord = venue.coordinate else { return }
        let region = MKCoordinateRegion(center: coord, latitudinalMeters: 800, longitudinalMeters: 800)
        mapView.setRegion(region, animated: true)
        if let match = mapView.annotations.first(where: { $0.coordinate.latitude == coord.latitude && $0.coordinate.longitude == coord.longitude }) {
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
        view.markerTintColor = Constants.Colors.primary
        view.canShowCallout = true
        return view
    }
}
