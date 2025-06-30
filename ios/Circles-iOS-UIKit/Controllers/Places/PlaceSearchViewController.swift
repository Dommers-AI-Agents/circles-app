import UIKit
import MapKit
import CoreLocation

// MARK: - PlaceSearchCell

class PlaceSearchCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCell() {
        textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        textLabel?.numberOfLines = 1
        
        detailTextLabel?.font = UIFont.systemFont(ofSize: 14)
        detailTextLabel?.textColor = .systemGray
        detailTextLabel?.numberOfLines = 2
    }
}

class PlaceSearchViewController: UIViewController {
    
    // MARK: - Properties
    weak var delegate: PlaceSearchDelegate?
    private var searchCompleter = MKLocalSearchCompleter()
    private var searchResults: [MKLocalSearchCompletion] = []
    private var currentLocation: CLLocation?
    
    // MARK: - UI Elements
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search for a place"
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        return searchBar
    }()
    
    private let tableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    private let mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.isHidden = true
        return mapView
    }()
    
    private let segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["List", "Map"])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupSearchCompleter()
        LocationService.shared.requestAuthorization()
        getCurrentLocation()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = Constants.Colors.background
        title = "Search Place"
        
        // Navigation items
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelButtonTapped)
        )
        
        // Add subviews
        view.addSubview(searchBar)
        view.addSubview(segmentedControl)
        view.addSubview(tableView)
        view.addSubview(mapView)
        
        // Configure table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PlaceSearchCell.self, forCellReuseIdentifier: "PlaceCell")
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        
        // Configure search bar
        searchBar.delegate = self
        
        // Configure segmented control
        segmentedControl.addTarget(self, action: #selector(segmentedControlChanged), for: .valueChanged)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            segmentedControl.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: Constants.Spacing.small),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.Spacing.large),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.Spacing.large),
            
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: Constants.Spacing.small),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            mapView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: Constants.Spacing.small),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupSearchCompleter() {
        searchCompleter.delegate = self
        searchCompleter.resultTypes = .pointOfInterest
        
        // Set region if we have current location
        if let location = currentLocation {
            searchCompleter.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 50000,
                longitudinalMeters: 50000
            )
        }
    }
    
    private func getCurrentLocation() {
        LocationService.shared.getCurrentLocation { [weak self] location in
            guard let self = self, let location = location else { return }
            self.currentLocation = location
            self.updateSearchCompleterRegion()
        }
    }
    
    private func updateSearchCompleterRegion() {
        if let location = currentLocation {
            searchCompleter.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 50000,
                longitudinalMeters: 50000
            )
            
            // Center map on current location
            let region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
            mapView.setRegion(region, animated: false)
        }
    }
    
    // MARK: - Actions
    
    @objc private func cancelButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func segmentedControlChanged() {
        let showMap = segmentedControl.selectedSegmentIndex == 1
        tableView.isHidden = showMap
        mapView.isHidden = !showMap
        
        if showMap {
            showSearchResultsOnMap()
        }
    }
    
    private func showSearchResultsOnMap() {
        // Remove existing annotations
        mapView.removeAnnotations(mapView.annotations)
        
        // Add annotations for search results
        for result in searchResults {
            let searchRequest = MKLocalSearch.Request(completion: result)
            let search = MKLocalSearch(request: searchRequest)
            
            search.start { [weak self] response, error in
                guard let self = self,
                      let response = response,
                      let mapItem = response.mapItems.first else { return }
                
                let annotation = MKPointAnnotation()
                annotation.coordinate = mapItem.placemark.coordinate
                annotation.title = mapItem.name
                annotation.subtitle = result.subtitle
                self.mapView.addAnnotation(annotation)
            }
        }
    }
    
    private func selectPlace(at indexPath: IndexPath) {
        let selectedResult = searchResults[indexPath.row]
        
        // Show loading indicator
        let loadingAlert = UIAlertController(title: "Loading", message: "Getting place details...", preferredStyle: .alert)
        present(loadingAlert, animated: true)
        
        // Perform detailed search
        let searchRequest = MKLocalSearch.Request(completion: selectedResult)
        let search = MKLocalSearch(request: searchRequest)
        
        search.start { [weak self] response, error in
            loadingAlert.dismiss(animated: true) {
                guard let self = self else { return }
                
                if let error = error {
                    self.showAlert(title: "Error", message: error.localizedDescription)
                    return
                }
                
                guard let response = response,
                      let mapItem = response.mapItems.first else {
                    self.showAlert(title: "Error", message: "Could not get place details")
                    return
                }
                
                // Try to get more detailed information
                self.fetchAdditionalPlaceInfo(for: mapItem) { enrichedMapItem in
                    self.handlePlaceSelection(enrichedMapItem)
                }
            }
        }
    }
    
    private func fetchAdditionalPlaceInfo(for mapItem: MKMapItem, completion: @escaping (MKMapItem) -> Void) {
        // In a real implementation with Google Places API, we would fetch additional details here
        // For now, we'll work with what MapKit provides
        completion(mapItem)
    }
    
    private func getCategoryDescription(for category: MKPointOfInterestCategory) -> String {
        switch category {
        case .restaurant: return "A dining establishment"
        case .cafe: return "A coffee shop or casual dining spot"
        case .nightlife, .brewery, .winery: return "A bar or nightlife venue"
        case .hotel, .campground: return "Accommodation services"
        case .store, .foodMarket: return "Retail shopping location"
        case .gasStation, .evCharger: return "Vehicle fueling or charging station"
        case .parking: return "Parking facility"
        case .carRental: return "Car rental services"
        case .laundry: return "Laundry services"
        case .postOffice: return "Postal services"
        case .bank, .atm: return "Banking and financial services"
        case .pharmacy: return "Pharmacy and medication services"
        case .hospital: return "Healthcare services"
        case .fireStation, .police: return "Emergency services"
        case .publicTransport: return "Public transportation"
        case .school, .university: return "Educational institution"
        case .library: return "Library and information services"
        case .movieTheater: return "Movie theater entertainment"
        case .museum: return "Museum and cultural exhibits"
        case .park, .beach, .nationalPark: return "Outdoor recreation area"
        case .theater: return "Theater and performing arts venue"
        case .zoo, .aquarium: return "Animal exhibits and attractions"
        case .amusementPark: return "Amusement park and rides"
        case .stadium: return "Sports and event venue"
        case .marina: return "Marina and boating services"
        default:
            if #available(iOS 18.0, *) {
                switch category {
                case .miniGolf: return "Mini golf recreation"
                case .castle, .landmark: return "Historical landmark or attraction"
                default: return "Local business or point of interest"
                }
            } else {
                return "Local business or point of interest"
            }
        }
    }
    
    private func handlePlaceSelection(_ mapItem: MKMapItem) {
        let placemark = mapItem.placemark
        let name = mapItem.name ?? "Unknown Place"
        let address = [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode,
            placemark.country
        ].compactMap { $0 }.joined(separator: ", ")
        
        let coordinate = placemark.coordinate
        let phone = mapItem.phoneNumber
        let website = mapItem.url?.absoluteString
        
        // Generate description based on category and available information
        var description: String?
        if let poiCategory = mapItem.pointOfInterestCategory {
            description = getCategoryDescription(for: poiCategory)
            
            // Add location context to description
            if let locality = placemark.locality {
                description! += " located in \(locality)"
            }
            
            if let areasOfInterest = placemark.areasOfInterest, !areasOfInterest.isEmpty {
                description! += ", near \(areasOfInterest.joined(separator: " and "))"
            }
        } else if let areasOfInterest = placemark.areasOfInterest {
            description = "Located near \(areasOfInterest.joined(separator: " and "))"
        }
        
        // Determine category with improved logic
        var category: String?
        if let poiCategory = mapItem.pointOfInterestCategory {
            switch poiCategory {
            case .restaurant: category = "Restaurant"
            case .cafe: category = "Cafe"
            case .nightlife, .brewery, .winery: category = "Bar"
            case .hotel, .campground: category = "Hotel"
            case .store, .foodMarket: category = "Retail"
            case .gasStation, .evCharger, .parking, .carRental,
                 .laundry, .postOffice, .bank, .atm, .pharmacy, .hospital,
                 .fireStation, .police, .publicTransport,
                 .school, .university, .library, .movieTheater:
                category = "Service"
            case .museum, .park, .beach, .theater, .zoo, .aquarium, .amusementPark,
                 .stadium, .marina, .nationalPark:
                category = "Attraction"
            default:
                if #available(iOS 18.0, *) {
                    switch poiCategory {
                    case .miniGolf:
                        category = "Attraction"
                    case .castle, .landmark:
                        category = "Attraction"
                    default:
                        category = "Other"
                    }
                } else {
                    category = "Other"
                }
            }
        }
        
        // If we have a name but no specific category, try to infer from the name
        if category == nil || category == "Other" {
            let lowerName = name.lowercased()
            if lowerName.contains("restaurant") || lowerName.contains("kitchen") || lowerName.contains("grill") {
                category = "Restaurant"
            } else if lowerName.contains("cafe") || lowerName.contains("coffee") {
                category = "Cafe"
            } else if lowerName.contains("bar") || lowerName.contains("pub") || lowerName.contains("brewery") {
                category = "Bar"
            } else if lowerName.contains("hotel") || lowerName.contains("inn") || lowerName.contains("motel") {
                category = "Hotel"
            } else if lowerName.contains("salon") || lowerName.contains("barber") || lowerName.contains("spa") ||
                      lowerName.contains("clinic") || lowerName.contains("dental") || lowerName.contains("medical") ||
                      lowerName.contains("repair") || lowerName.contains("service") || lowerName.contains("bank") ||
                      lowerName.contains("insurance") || lowerName.contains("law") || lowerName.contains("attorney") {
                category = "Service"
            } else if lowerName.contains("park") || lowerName.contains("museum") || lowerName.contains("theater") {
                category = "Attraction"
            }
        }
        
        // Notify delegate
        delegate?.didSelectPlace(
            name: name,
            address: address,
            coordinate: coordinate,
            phone: phone,
            website: website,
            category: category,
            description: description
        )
        
        // Dismiss
        dismiss(animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension PlaceSearchViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PlaceCell", for: indexPath)
        let result = searchResults[indexPath.row]
        
        cell.textLabel?.text = result.title
        cell.detailTextLabel?.text = result.subtitle
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension PlaceSearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        selectPlace(at: indexPath)
    }
}

// MARK: - UISearchBarDelegate

extension PlaceSearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchCompleter.queryFragment = searchText
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension PlaceSearchViewController: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results
        tableView.reloadData()
        
        if segmentedControl.selectedSegmentIndex == 1 {
            showSearchResultsOnMap()
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search completer error: \(error.localizedDescription)")
    }
}