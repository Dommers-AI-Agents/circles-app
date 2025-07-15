import UIKit
import MapKit

protocol PlaceAddressSearchViewControllerDelegate: AnyObject {
    func placeAddressSearchViewController(_ controller: PlaceAddressSearchViewController, didSelectMapItem mapItem: MKMapItem)
    func placeAddressSearchViewControllerDidCancel(_ controller: PlaceAddressSearchViewController)
}

class PlaceAddressSearchViewController: BaseViewController {
    
    // MARK: - Properties
    weak var delegate: PlaceAddressSearchViewControllerDelegate?
    private let searchCompleter = MKLocalSearchCompleter()
    private var searchResults: [MKLocalSearchCompletion] = []
    private let placeName: String
    private let currentLocation: CLLocation?
    
    // MARK: - Configuration
    override var loadsDataOnViewDidLoad: Bool { false }
    
    // MARK: - UI Elements
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search for correct location"
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    private let instructionLabel: UILabel = {
        let label = UILabel()
        label.text = "Search for the correct location of this place"
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .systemGray
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.register(UITableViewCell.self, forCellReuseIdentifier: "SearchResultCell")
        return table
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // MARK: - Initialization
    init(placeName: String, currentLocation: CLLocation? = nil) {
        self.placeName = placeName
        self.currentLocation = currentLocation
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigationBar()
        setupDelegates()
        setupSearchCompleter()
        
        // Start with place name search
        searchBar.text = placeName
        performSearch(query: placeName)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(searchBar)
        view.addSubview(instructionLabel)
        view.addSubview(tableView)
        view.addSubview(loadingIndicator)
        
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            instructionLabel.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 8),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            tableView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func setupNavigationBar() {
        title = "Update Location"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
    }
    
    private func setupDelegates() {
        searchBar.delegate = self
        tableView.delegate = self
        tableView.dataSource = self
        searchCompleter.delegate = self
    }
    
    private func setupSearchCompleter() {
        searchCompleter.resultTypes = [.pointOfInterest, .address]
        
        // Set search region based on current location if available
        if let location = currentLocation {
            searchCompleter.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 10000, // 10km radius
                longitudinalMeters: 10000
            )
        }
    }
    
    // MARK: - Actions
    @objc private func cancelTapped() {
        delegate?.placeAddressSearchViewControllerDidCancel(self)
        dismiss(animated: true)
    }
    
    // MARK: - Search
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            tableView.reloadData()
            return
        }
        
        searchCompleter.queryFragment = query
    }
    
    private func performLocalSearch(for completion: MKLocalSearchCompletion) {
        loadingIndicator.startAnimating()
        tableView.isUserInteractionEnabled = false
        
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        
        search.start { [weak self] response, error in
            self?.loadingIndicator.stopAnimating()
            self?.tableView.isUserInteractionEnabled = true
            
            if let error = error {
                print("Local search error: \(error)")
                self?.showError("Unable to find place details. Please try again.")
                return
            }
            
            guard let mapItem = response?.mapItems.first else {
                self?.showError("No results found. Please try a different search.")
                return
            }
            
            // Confirm selection with user
            self?.confirmSelection(mapItem: mapItem)
        }
    }
    
    private func confirmSelection(mapItem: MKMapItem) {
        let placemark = mapItem.placemark
        let name = mapItem.name ?? placeName
        
        // Format address
        let address = [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode
        ].compactMap { $0 }.joined(separator: ", ")
        
        let alert = UIAlertController(
            title: "Confirm Location",
            message: "Update to this location?\n\n\(name)\n\(address)",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Update", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.placeAddressSearchViewController(self, didSelectMapItem: mapItem)
            self.dismiss(animated: true)
        })
        
        present(alert, animated: true)
    }
    
}

// MARK: - UISearchBarDelegate
extension PlaceAddressSearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        performSearch(query: searchText)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - UITableViewDataSource
extension PlaceAddressSearchViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
        let result = searchResults[indexPath.row]
        
        var content = cell.defaultContentConfiguration()
        content.text = result.title
        content.secondaryText = result.subtitle
        content.image = UIImage(systemName: "mappin.circle.fill")
        content.imageProperties.tintColor = .systemBlue
        
        cell.contentConfiguration = content
        return cell
    }
}

// MARK: - UITableViewDelegate
extension PlaceAddressSearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let completion = searchResults[indexPath.row]
        performLocalSearch(for: completion)
    }
}

// MARK: - MKLocalSearchCompleterDelegate
extension PlaceAddressSearchViewController: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results
        tableView.reloadData()
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search completer error: \(error)")
        // Don't show error to user for completer failures as they're common during typing
    }
}