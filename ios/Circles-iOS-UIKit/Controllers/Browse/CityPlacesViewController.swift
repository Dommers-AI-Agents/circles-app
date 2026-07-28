import UIKit
import MapKit

/// Map pin carrying its venue so the marker can show the category glyph, the
/// callout can name who added it, and tapping through can open the place page.
final class VenueAnnotation: MKPointAnnotation {
    let venue: CityVenue
    var category: PlaceCategory { PlaceCategory(rawValue: venue.category) ?? .other }
    init(venue: CityVenue) {
        self.venue = venue
        super.init()
    }
}

/// Third level of the location lens: every venue in a city, drawn from ALL the
/// user's network (own + shared), each showing who added it and its rating.
/// Filter by People (Everyone / Me / a connection) and by category; tap a row or
/// a pin to open the real place page (back returns to the filtered view).
final class CityPlacesViewController: BaseTableViewController {

    private let cityKey: String
    private let titleText: String
    private var allVenues: [CityVenue] = []
    private var people: [BrowsePerson] = []
    private var selectedGroup: PlaceCategoryGroup = .all
    private var selectedPersonId: String = PeopleFilter.everyone

    private enum PeopleFilter { static let everyone = "__all"; static let me = "me" }

    private let mapView: MKMapView = {
        let m = MKMapView()
        m.isRotateEnabled = false
        m.isPitchEnabled = false
        m.autoresizingMask = [.flexibleWidth]
        return m
    }()
    private let peopleBar: BrowseChipBar = {
        let b = BrowseChipBar(); b.autoresizingMask = [.flexibleWidth]; return b
    }()
    private let chipBar: CategoryChipBar = {
        let bar = CategoryChipBar(); bar.autoresizingMask = [.flexibleWidth]; return bar
    }()

    private let mapHeight: CGFloat = 200
    private let barHeight: CGFloat = 48

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
        tableView.estimatedRowHeight = 84
        mapView.delegate = self
        chipBar.onSelect = { [weak self] group in self?.selectedGroup = group; self?.refresh() }
        peopleBar.onSelect = { [weak self] id in self?.selectedPersonId = id; self?.refresh() }
        buildHeader(showPeople: false)
    }

    private func buildHeader(showPeople: Bool) {
        let width = view.bounds.width
        let height = mapHeight + (showPeople ? barHeight : 0) + barHeight
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        container.autoresizingMask = [.flexibleWidth]

        mapView.frame = CGRect(x: 0, y: 0, width: width, height: mapHeight)
        container.addSubview(mapView)
        var y = mapHeight
        if showPeople {
            peopleBar.frame = CGRect(x: 0, y: y, width: width, height: barHeight)
            container.addSubview(peopleBar)
            y += barHeight
        }
        chipBar.frame = CGRect(x: 0, y: y, width: width, height: barHeight)
        container.addSubview(chipBar)

        tableView.tableHeaderView = container
    }

    // MARK: - Data

    private var filteredVenues: [CityVenue] {
        allVenues.filter { venue in
            let categoryOK = selectedGroup == .all || selectedGroup.matches(venue.category)
            let personOK: Bool
            switch selectedPersonId {
            case PeopleFilter.everyone: personOK = true
            case PeopleFilter.me:       personOK = venue.savedByMe
            default:                    personOK = venue.savers.contains { $0.id == selectedPersonId }
            }
            return categoryOK && personOK
        }
    }

    override func loadData(completion: (() -> Void)? = nil) {
        BrowseService.shared.getCityPlaces(cityKey: cityKey) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { completion?(); return }
                switch result {
                case .success(let resp):
                    self.allVenues = resp.places
                    self.people = resp.people
                    self.chipBar.setGroups(PlaceCategoryGroup.present(in: self.allVenues.map { $0.category }), selected: .all)
                    self.configurePeopleBar()
                    self.refresh()
                    if self.allVenues.isEmpty { self.showEmptyState() }
                case .failure(let error):
                    self.showError(error)
                }
                completion?()
            }
        }
    }

    /// Build the People filter (Everyone / Me / each connection with places here).
    /// Only shown when someone besides you has a place in this city.
    private func configurePeopleBar() {
        guard !people.isEmpty else { buildHeader(showPeople: false); return }
        var items: [BrowseChipBar.Item] = [
            .init(id: PeopleFilter.everyone, title: "Everyone"),
            .init(id: PeopleFilter.me, title: "Me")
        ]
        items += people.map { .init(id: $0.id, title: $0.name) }
        peopleBar.setItems(items, selectedId: selectedPersonId)
        buildHeader(showPeople: true)
    }

    private func refresh() {
        tableView.reloadData()
        updateMap()
        updateHeaderStat()
    }

    private func updateHeaderStat() {
        let venues = filteredVenues
        let noun = selectedGroup == .all ? (venues.count == 1 ? "pin" : "pins") : selectedGroup.title.lowercased()
        var text = "\(venues.count) \(noun)"
        if let hood = densestNeighborhood(in: venues) { text += " · Most in \(hood)" }
        navigationItem.prompt = text
    }

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
            let a = VenueAnnotation(venue: venue)
            a.coordinate = coord
            a.title = venue.name
            // Callout subtitle: who added it (+ rating when present).
            a.subtitle = [venue.ratingText, venue.addedByText].compactMap { $0 }.joined(separator: " · ")
            return a
        }
        mapView.addAnnotations(annotations)
        if !annotations.isEmpty { mapView.showAnnotations(annotations, animated: false) }
    }

    /// Fetch the full place and push the real place page. Back returns here with
    /// the current filters intact (it's the same nav stack).
    private func openPlace(_ venue: CityVenue) {
        let loading = AlertPresenter.showLoading(from: self)
        PlaceService.shared.fetchPlaceById(id: venue.placeId) { [weak self] result in
            DispatchQueue.main.async {
                loading.dismiss(animated: false) {
                    guard let self = self else { return }
                    switch result {
                    case .success(let place):
                        self.navigationController?.pushViewController(PlaceDetailViewController(place: place), animated: true)
                    case .failure(let error):
                        self.showError(error)
                    }
                }
            }
        }
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
        openPlace(filteredVenues[indexPath.row])
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
        view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
        if let venue = annotation as? VenueAnnotation {
            view.markerTintColor = venue.category.color
            view.glyphImage = UIImage(systemName: venue.category.systemIconName)
        } else {
            view.markerTintColor = Constants.Colors.primary
        }
        return view
    }

    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        if let venue = (view.annotation as? VenueAnnotation)?.venue { openPlace(venue) }
    }
}
