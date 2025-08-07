import UIKit
import MapKit
import CoreLocation

class VisitHistoryViewController: BaseViewController {
    
    // MARK: - Properties
    private var visits: [PlaceVisit] = []
    private var filteredVisits: [PlaceVisit] = []
    private var selectedVisits: Set<String> = []
    private var isSelectionMode = false
    private var currentFilter: VisitFilter = .today
    private var isMapView = false
    
    enum VisitFilter: String, CaseIterable {
        case all = "All"
        case unreviewed = "Unreviewed"
        case reviewed = "Reviewed"
        case today = "Today"
        case thisWeek = "This Week"
        
        var title: String { rawValue }
    }
    
    // MARK: - UI Elements
    private lazy var statusView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.systemGray6
        view.layer.cornerRadius = 8
        
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.alignment = .leading
        
        let titleLabel = UILabel()
        titleLabel.text = "Visit Tracking Status"
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .label
        
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(statusLabel)
        
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
        
        return view
    }()
    
    private let statusLabel = UILabel()
    
    private lazy var filterSegmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["Today", "Unreviewed", "All"])
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.register(VisitCell.self, forCellReuseIdentifier: "VisitCell")
        table.separatorStyle = .none
        table.backgroundColor = .systemGroupedBackground
        table.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 20, right: 0)
        return table
    }()
    
    private lazy var mapView: MKMapView = {
        let map = MKMapView()
        map.translatesAutoresizingMaskIntoConstraints = false
        map.delegate = self
        map.showsUserLocation = true
        map.isHidden = true
        return map
    }()
    
    private lazy var selectionToolbar: UIToolbar = {
        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.isHidden = true
        return toolbar
    }()
    
    private lazy var selectButton = UIBarButtonItem(
        title: "Select",
        style: .plain,
        target: self,
        action: #selector(toggleSelectionMode)
    )
    
    private lazy var addToCircleButton = UIBarButtonItem(
        title: "Add to Circle",
        style: .done,
        target: self,
        action: #selector(addSelectedToCircle)
    )
    
    // MARK: - BaseViewController Configuration
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { 
        switch currentFilter {
        case .unreviewed:
            return "No unreviewed visits\n\nVisit some places and they'll appear here!"
        case .today:
            return "No visits today\n\nGet out and explore!"
        default:
            return "No visits recorded\n\nEnable visit tracking to automatically save places you visit"
        }
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        checkTrackingStatus()
        
        // Listen for history cleared notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHistoryCleared),
            name: NSNotification.Name("VisitHistoryCleared"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
        updateTrackingStatus()
    }
    
    // MARK: - Setup
    private func setupView() {
        title = "My Visits"
        view.backgroundColor = .systemGroupedBackground
        
        navigationItem.rightBarButtonItems = [
            selectButton,
            UIBarButtonItem(
                image: UIImage(systemName: "gear"),
                style: .plain,
                target: self,
                action: #selector(showSettings)
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "map"),
                style: .plain,
                target: self,
                action: #selector(toggleMapView)
            )
        ]
        
        // Add subviews
        view.addSubview(statusView)
        view.addSubview(filterSegmentedControl)
        view.addSubview(tableView)
        view.addSubview(mapView)
        view.addSubview(selectionToolbar)
        
        // Setup toolbar
        setupSelectionToolbar()
        
        NSLayoutConstraint.activate([
            statusView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            filterSegmentedControl.topAnchor.constraint(equalTo: statusView.bottomAnchor, constant: 12),
            filterSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            filterSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            tableView.topAnchor.constraint(equalTo: filterSegmentedControl.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: selectionToolbar.topAnchor),
            
            mapView.topAnchor.constraint(equalTo: filterSegmentedControl.bottomAnchor, constant: 8),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: selectionToolbar.topAnchor),
            
            selectionToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectionToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectionToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            selectionToolbar.heightAnchor.constraint(equalToConstant: 49)
        ])
        
        updateTrackingStatus()
    }
    
    private func setupSelectionToolbar() {
        let dismissButton = UIBarButtonItem(
            title: "Dismiss",
            style: .plain,
            target: self,
            action: #selector(dismissSelected)
        )
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        let selectedLabel = UIBarButtonItem(
            title: "0 selected",
            style: .plain,
            target: nil,
            action: nil
        )
        selectedLabel.isEnabled = false
        selectedLabel.tag = 100 // For updating later
        
        selectionToolbar.items = [
            dismissButton,
            flexSpace,
            selectedLabel,
            flexSpace,
            addToCircleButton
        ]
    }
    
    // MARK: - Data Loading
    override func loadData(completion: (() -> Void)? = nil) {
        APIService.shared.request(
            endpoint: "visits",
            method: .get,
            queryParams: [
                "limit": "100",
                "reviewed": currentFilter == .unreviewed ? "false" : nil,
                "startDate": getFilterStartDate()
            ].compactMapValues { $0 },
            requiresAuth: true
        ) { [weak self] (result: Result<VisitsResponse, APIError>) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                completion?()
                
                switch result {
                case .success(let response):
                    self.visits = response.data.map { PlaceVisit.from($0) }
                    self.applyFilter()
                    self.tableView.reloadData()
                    if self.filteredVisits.isEmpty {
                        self.showEmptyState()
                    } else {
                        self.hideEmptyState()
                    }
                    
                    // Update map if visible
                    if self.isMapView {
                        self.updateMapAnnotations()
                    }
                    
                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }
    
    private func updateMapAnnotations() {
        // Remove existing annotations
        mapView.removeAnnotations(mapView.annotations)
        
        // Add new annotations for filtered visits
        let annotations = filteredVisits.filter { !$0.dismissed }.map { visit -> MKPointAnnotation in
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: visit.latitude, longitude: visit.longitude)
            annotation.title = visit.placeName
            annotation.subtitle = visit.placeAddress
            return annotation
        }
        
        mapView.addAnnotations(annotations)
        
        // Adjust map region to show all annotations
        if !annotations.isEmpty {
            let coordinates = annotations.map { $0.coordinate }
            let minLat = coordinates.min { $0.latitude < $1.latitude }?.latitude ?? 0
            let maxLat = coordinates.max { $0.latitude < $1.latitude }?.latitude ?? 0
            let minLon = coordinates.min { $0.longitude < $1.longitude }?.longitude ?? 0
            let maxLon = coordinates.max { $0.longitude < $1.longitude }?.longitude ?? 0
            
            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            
            let span = MKCoordinateSpan(
                latitudeDelta: max(0.01, (maxLat - minLat) * 1.5),
                longitudeDelta: max(0.01, (maxLon - minLon) * 1.5)
            )
            
            mapView.setRegion(MKCoordinateRegion(center: center, span: span), animated: true)
        }
    }
    
    private func getFilterStartDate() -> String? {
        switch currentFilter {
        case .today:
            return ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        case .thisWeek:
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return ISO8601DateFormatter().string(from: weekAgo)
        default:
            return nil
        }
    }
    
    // MARK: - Filtering
    private func applyFilter() {
        switch currentFilter {
        case .all:
            filteredVisits = visits
        case .unreviewed:
            filteredVisits = visits.filter { !$0.reviewed && !$0.dismissed }
        case .reviewed:
            filteredVisits = visits.filter { $0.reviewed }
        case .today:
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            filteredVisits = visits.filter {
                calendar.isDate($0.visitedAt, inSameDayAs: today)
            }
        case .thisWeek:
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            filteredVisits = visits.filter { $0.visitedAt >= weekAgo }
        }
    }
    
    @objc private func filterChanged() {
        switch filterSegmentedControl.selectedSegmentIndex {
        case 0:
            currentFilter = .today
        case 1:
            currentFilter = .unreviewed
        case 2:
            currentFilter = .all
        default:
            currentFilter = .today
        }
        
        loadData()
    }
    
    // MARK: - Selection Mode
    @objc private func toggleSelectionMode() {
        isSelectionMode.toggle()
        selectedVisits.removeAll()
        
        selectButton.title = isSelectionMode ? "Cancel" : "Select"
        selectionToolbar.isHidden = !isSelectionMode
        tableView.allowsMultipleSelection = isSelectionMode
        
        // Update visible cells
        tableView.reloadData()
        updateSelectionCount()
    }
    
    private func updateSelectionCount() {
        if let label = selectionToolbar.items?.first(where: { $0.tag == 100 }) {
            label.title = "\(selectedVisits.count) selected"
        }
        
        addToCircleButton.isEnabled = !selectedVisits.isEmpty
    }
    
    // MARK: - Actions
    @objc private func showSettings() {
        let settingsVC = VisitTrackingSettingsViewController()
        let nav = UINavigationController(rootViewController: settingsVC)
        present(nav, animated: true)
    }
    
    @objc private func toggleMapView() {
        isMapView.toggle()
        
        UIView.transition(with: view, duration: 0.3, options: .transitionCrossDissolve, animations: {
            self.tableView.isHidden = self.isMapView
            self.mapView.isHidden = !self.isMapView
            self.selectButton.isEnabled = !self.isMapView
            
            // Update toggle button icon
            if let mapButton = self.navigationItem.rightBarButtonItems?.first(where: { $0.action == #selector(self.toggleMapView) }) {
                mapButton.image = UIImage(systemName: self.isMapView ? "list.bullet" : "map")
            }
        })
        
        if isMapView {
            updateMapAnnotations()
        }
    }
    
    @objc private func handleHistoryCleared() {
        // Clear the visits array and reload
        visits.removeAll()
        filteredVisits.removeAll()
        tableView.reloadData()
        showEmptyState()
    }
    
    // MARK: - Tracking Status
    private func updateTrackingStatus() {
        let locationManager = CLLocationManager()
        let authStatus = locationManager.authorizationStatus
        let trackingEnabled = VisitDetectionService.shared.isTrackingEnabled
        
        var statusText = ""
        var statusColor = UIColor.secondaryLabel
        
        switch authStatus {
        case .authorizedAlways:
            if trackingEnabled {
                statusText = "✅ Tracking enabled - Location: Always allowed"
                statusColor = .systemGreen
            } else {
                statusText = "⏸️ Tracking disabled - Enable in settings"
                statusColor = .systemOrange
            }
        case .authorizedWhenInUse:
            statusText = "⚠️ Limited tracking - Grant 'Always Allow' location permission"
            statusColor = .systemOrange
        case .denied, .restricted:
            statusText = "❌ Location access denied - Enable in Settings app"
            statusColor = .systemRed
        case .notDetermined:
            statusText = "📍 Location permission not requested"
            statusColor = .systemGray
        @unknown default:
            statusText = "Unknown location status"
        }
        
        statusLabel.text = statusText
        statusLabel.textColor = statusColor
        
        // Update background color based on status
        if authStatus == .authorizedAlways && trackingEnabled {
            statusView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.1)
        } else {
            statusView.backgroundColor = UIColor.systemGray6
        }
    }
    
    @objc private func addSelectedToCircle() {
        guard !selectedVisits.isEmpty else { return }
        
        let circlePickerVC = VisitCirclePickerViewController()
        circlePickerVC.onCirclesSelected = { [weak self] circleIds in
            self?.addVisitsToCircles(visitIds: Array(self?.selectedVisits ?? []), circleIds: circleIds)
        }
        
        let nav = UINavigationController(rootViewController: circlePickerVC)
        present(nav, animated: true)
    }
    
    @objc private func dismissSelected() {
        guard !selectedVisits.isEmpty else { return }
        
        showConfirmation(
            title: "Dismiss Visits?",
            message: "These visits will be removed from your history.",
            confirmTitle: "Dismiss",
            isDestructive: true
        ) { [weak self] in
            self?.dismissVisits(Array(self?.selectedVisits ?? []))
        }
    }
    
    private func addVisitsToCircles(visitIds: [String], circleIds: [String]) {
        let loading = showLoading()
        
        APIService.shared.request(
            endpoint: "visits/bulk-add",
            method: .post,
            body: [
                "visitIds": visitIds,
                "circleIds": circleIds
            ],
            requiresAuth: true
        ) { [weak self] (result: Result<BulkAddResponse, APIError>) in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    switch result {
                    case .success(let response):
                        self?.showSuccess("Added \(response.results.added.count) places to circles!")
                        self?.toggleSelectionMode()
                        self?.loadData()
                        
                    case .failure(let error):
                        self?.showError(error)
                    }
                }
            }
        }
    }
    
    private func dismissVisits(_ visitIds: [String]) {
        for visitId in visitIds {
            APIService.shared.request(
                endpoint: "visits/\(visitId)",
                method: .put,
                body: ["dismissed": true],
                requiresAuth: true
            ) { [weak self] (result: Result<VisitResponse, APIError>) in
                if case .failure(let error) = result {
                    self?.showError(error)
                }
            }
        }
        
        // Remove from local list immediately
        visits.removeAll { visitIds.contains($0.id) }
        applyFilter()
        tableView.reloadData()
        toggleSelectionMode()
    }
    
    private func dismissSingleVisit(_ visit: PlaceVisit) {
        // Show loading indicator
        let loading = showLoading()
        
        APIService.shared.request(
            endpoint: "visits/\(visit.id)",
            method: .put,
            body: ["dismissed": true],
            requiresAuth: true
        ) { [weak self] (result: Result<VisitResponse, APIError>) in
            DispatchQueue.main.async {
                loading.dismiss(animated: true) {
                    switch result {
                    case .success:
                        // Update the visit locally
                        if let index = self?.visits.firstIndex(where: { $0.id == visit.id }) {
                            self?.visits[index].dismissed = true
                        }
                        self?.applyFilter()
                        self?.tableView.reloadData()
                        
                        // Update map if visible
                        if self?.isMapView == true {
                            self?.updateMapAnnotations()
                        }
                        
                        self?.showSuccess("Visit dismissed")
                        
                    case .failure(let error):
                        self?.showError(error)
                    }
                }
            }
        }
    }
    
    private func checkTrackingStatus() {
        guard !VisitDetectionService.shared.isTrackingEnabled else { return }
        
        let alert = UIAlertController(
            title: "Enable Visit Tracking?",
            message: "Circles can automatically track places you visit so you can review and save them later.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Enable", style: .default) { _ in
            VisitDetectionService.shared.setTrackingEnabled(true)
        })
        
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
        
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension VisitHistoryViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredVisits.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "VisitCell", for: indexPath) as! VisitCell
        let visit = filteredVisits[indexPath.row]
        
        cell.configure(with: visit)
        cell.isInSelectionMode = isSelectionMode
        cell.isVisitSelected = selectedVisits.contains(visit.id)
        cell.delegate = self
        
        return cell
    }
}

// MARK: - UITableViewDelegate
extension VisitHistoryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let visit = filteredVisits[indexPath.row]
        
        if isSelectionMode {
            if selectedVisits.contains(visit.id) {
                selectedVisits.remove(visit.id)
            } else {
                selectedVisits.insert(visit.id)
            }
            
            tableView.reloadRows(at: [indexPath], with: .none)
            updateSelectionCount()
        } else {
            // Show visit details
            let detailVC = VisitDetailViewController(visit: visit)
            detailVC.onVisitUpdated = { [weak self] in
                self?.loadData()
            }
            navigationController?.pushViewController(detailVC, animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 100
    }
}

// MARK: - VisitCellDelegate
extension VisitHistoryViewController: VisitCellDelegate {
    func visitCell(_ cell: VisitCell, didToggleSelection visit: PlaceVisit) {
        if selectedVisits.contains(visit.id) {
            selectedVisits.remove(visit.id)
        } else {
            selectedVisits.insert(visit.id)
        }
        updateSelectionCount()
    }
    
    func visitCell(_ cell: VisitCell, didTapQuickAdd visit: PlaceVisit) {
        let circlePickerVC = VisitCirclePickerViewController()
        circlePickerVC.onCirclesSelected = { [weak self] circleIds in
            self?.addVisitsToCircles(visitIds: [visit.id], circleIds: circleIds)
        }
        
        let nav = UINavigationController(rootViewController: circlePickerVC)
        present(nav, animated: true)
    }
    
    func visitCell(_ cell: VisitCell, didTapDismiss visit: PlaceVisit) {
        // Show confirmation
        showConfirmation(
            title: "Dismiss Visit?",
            message: "This will remove the visit from your view but keep it in your export history.",
            confirmTitle: "Dismiss",
            isDestructive: true
        ) { [weak self] in
            self?.dismissSingleVisit(visit)
        }
    }
}

// MARK: - Response Models
struct VisitsResponse: Codable {
    let success: Bool
    let data: [VisitData]
    let pagination: PaginationInfo?
}

struct PaginationInfo: Codable {
    let total: Int
    let limit: Int
    let offset: Int
    let hasMore: Bool
}

struct BulkAddResponse: Codable {
    let success: Bool
    let results: BulkAddResults
}

struct BulkAddResults: Codable {
    let added: [AddedVisit]
    let failed: [FailedVisit]
}

struct AddedVisit: Codable {
    let visitId: String
    let circleId: String
    let placeId: String
}

struct FailedVisit: Codable {
    let visitId: String
    let reason: String
}

// MARK: - MKMapViewDelegate
extension VisitHistoryViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Don't customize user location
        if annotation is MKUserLocation {
            return nil
        }
        
        let identifier = "VisitAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
            annotationView?.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            annotationView?.markerTintColor = Constants.Colors.primary
        } else {
            annotationView?.annotation = annotation
        }
        
        return annotationView
    }
    
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        guard let annotation = view.annotation,
              let visit = filteredVisits.first(where: { 
                  $0.latitude == annotation.coordinate.latitude && 
                  $0.longitude == annotation.coordinate.longitude 
              }) else { return }
        
        let detailVC = VisitDetailViewController(visit: visit)
        detailVC.onVisitUpdated = { [weak self] in
            self?.loadData()
        }
        navigationController?.pushViewController(detailVC, animated: true)
    }
}


