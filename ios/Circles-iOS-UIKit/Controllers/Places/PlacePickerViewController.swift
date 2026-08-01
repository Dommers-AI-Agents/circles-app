import UIKit
import CoreLocation

protocol PlacePickerViewControllerDelegate: AnyObject {
    func placePickerViewController(_ controller: PlacePickerViewController, didSelectPlace place: Place)
}

class PlacePickerViewController: BaseViewController {
    
    weak var delegate: PlacePickerViewControllerDelegate?
    private var places: [Place] = []
    private var isLoading = false

    /// Anchor for "closest first". Resolved quietly — the picker never prompts
    /// for location (see OneShotLocationProvider); with no fix we fall back to
    /// alphabetical rather than showing an arbitrary order.
    private let locationProvider = OneShotLocationProvider()
    private var origin: CLLocation?
    
    // MARK: - Configuration
    override var loadsDataOnViewDidLoad: Bool { false }
    override var emptyStateMessage: String? { "No places found.\nAdd places to your circles first." }
    
    // MARK: - UI Elements
    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private let loadingView: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private let emptyStateLabel: UILabel = {
        let label = UILabel()
        label.text = "No places found.\nAdd places to your circles first."
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    private let searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchBar.placeholder = "Search your places..."
        controller.obscuresBackgroundDuringPresentation = false
        controller.hidesNavigationBarDuringPresentation = false
        return controller
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupNavigationBar()
        loadPlaces()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Activate search immediately
        searchController.isActive = true
        searchController.searchBar.becomeFirstResponder()
    }
    
    // MARK: - Setup
    private func setupView() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)
        view.addSubview(loadingView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            
            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PlaceCell")
        
        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }
    
    private func setupNavigationBar() {
        title = "Select Place"
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
    }
    
    // MARK: - Data Loading
    private func loadPlaces() {
        guard !isLoading else { return }
        
        isLoading = true
        loadingView.startAnimating()
        tableView.isHidden = true
        emptyStateLabel.isHidden = true
        
        // First, fetch user's circles to get circle IDs
        CircleService.shared.fetchUserCircles { [weak self] result in
            switch result {
            case .success(let circles):
                // Now fetch places for each circle
                let group = DispatchGroup()
                var allFetchedPlaces: [Place] = []
                
                for circle in circles {
                    group.enter()
                    PlaceService.shared.fetchPlacesByCircleId(circleId: circle.id) { placeResult in
                        switch placeResult {
                        case .success(let places):
                            allFetchedPlaces.append(contentsOf: places)
                        case .failure(let error):
                            Logger.debug("Error fetching places for circle \(circle.id): \(error)")
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) { [weak self] in
                    guard let self = self else { return }
                    
                    self.isLoading = false
                    self.loadingView.stopAnimating()
                    self.tableView.isHidden = false
                    
                    // Remove duplicates based on place ID
                    let uniquePlaces = Array(Set(allFetchedPlaces))
                    self.places = self.sortedByDistance(uniquePlaces)
                    self.tableView.reloadData()
                    self.updateEmptyState()

                    // If the location fix lands after the list is drawn,
                    // re-sort in place rather than leaving it alphabetical.
                    if self.origin == nil {
                        self.locationProvider.requestLocation { [weak self] location in
                            DispatchQueue.main.async {
                                guard let self = self, let location = location else { return }
                                self.origin = location
                                self.places = self.sortedByDistance(self.places)
                                self.tableView.reloadData()
                            }
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    Logger.debug("Error loading circles: \(error)")
                    self.isLoading = false
                    self.loadingView.stopAnimating()
                    self.updateEmptyState()
                }
            }
        }
    }
    
    /// Closest first when we know where you are; alphabetical otherwise.
    /// Places with no coordinates sink to the bottom instead of sorting as if
    /// they were at (0, 0) — the Gulf of Guinea is not "nearby".
    private func sortedByDistance(_ input: [Place]) -> [Place] {
        guard let origin = origin else {
            return input.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return input.sorted { lhs, rhs in
            let lhsDistance = lhs.location?.clLocation.map { origin.distance(from: $0) }
            let rhsDistance = rhs.location?.clLocation.map { origin.distance(from: $0) }
            switch (lhsDistance, rhsDistance) {
            case let (l?, r?):
                return l == r
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : l < r
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil):
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    // MARK: - Filtering
    private var filteredPlaces: [Place] {
        guard let searchText = searchController.searchBar.text, !searchText.isEmpty else {
            return places
        }
        
        return places.filter { place in
            place.name.localizedCaseInsensitiveContains(searchText) ||
            place.address.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - UITableViewDataSource
extension PlacePickerViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredPlaces.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlaceCell", for: indexPath)
        let place = filteredPlaces[indexPath.row]
        
        var content = cell.defaultContentConfiguration()
        content.text = place.name
        content.secondaryText = place.address
        content.image = UIImage(systemName: "mappin.circle.fill")
        content.imageProperties.tintColor = Constants.Colors.primary
        
        cell.contentConfiguration = content
        return cell
    }
}

// MARK: - UITableViewDelegate
extension PlacePickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let place = filteredPlaces[indexPath.row]
        delegate?.placePickerViewController(self, didSelectPlace: place)
    }
}

// MARK: - UISearchResultsUpdating
extension PlacePickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        tableView.reloadData()
        updateEmptyState()
    }
}

// Make Place conform to Hashable for Set operations
extension Place: Hashable {
    static func == (lhs: Place, rhs: Place) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Private Methods
private extension PlacePickerViewController {
    func updateEmptyState() {
        let hasPlaces = !filteredPlaces.isEmpty
        tableView.isHidden = !hasPlaces
        emptyStateLabel.isHidden = hasPlaces
        
        if searchController.isActive && !hasPlaces && !(searchController.searchBar.text ?? "").isEmpty {
            emptyStateLabel.text = "No places found matching '\(searchController.searchBar.text ?? "")'"
        } else if !hasPlaces {
            emptyStateLabel.text = "No places found.\nAdd places to your circles first."
        }
    }
}